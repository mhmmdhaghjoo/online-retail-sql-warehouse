"""Simulate the raw exports of a small European online shop.

The data is synthetic on purpose: it can be published, it is reproducible
(fixed seed), and it contains the kind of defects a real export has
(duplicates, missing values, inconsistent spelling, invalid rows), so the
cleaning steps in the warehouse have something real to do.

Usage:
    python data/generate_data.py --out data/raw --seed 42
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

START = pd.Timestamp("2023-01-01")
END = pd.Timestamp("2025-12-31")

COUNTRIES = {"DE": 0.46, "AT": 0.12, "CH": 0.10, "NL": 0.12, "FR": 0.12, "IT": 0.08}
CHANNELS = {"organic": 0.30, "paid_search": 0.25, "social": 0.20, "referral": 0.10, "email": 0.15}

# Latent customer types. They are NOT exported; they only drive behaviour.
# name: (share, orders per year while active, mean active lifetime in days)
SEGMENTS = {
    "loyal": (0.12, 9.0, 900),
    "regular": (0.28, 4.0, 500),
    "occasional": (0.35, 1.5, 300),
    "one_time": (0.25, 0.3, 60),
}

# category: (number of products, median price in EUR, gross margin)
CATEGORIES = {
    "Electronics": (30, 120.0, 0.22),
    "Home & Kitchen": (35, 45.0, 0.40),
    "Fashion": (40, 38.0, 0.55),
    "Beauty": (25, 22.0, 0.60),
    "Sports": (25, 50.0, 0.42),
    "Books": (20, 16.0, 0.30),
    "Toys": (15, 28.0, 0.45),
    "Garden": (10, 60.0, 0.38),
}

# Relative demand per calendar month (Black Friday / Christmas peak).
SEASONALITY = np.array([0.85, 0.80, 0.90, 0.95, 1.00, 0.95, 0.90, 0.90, 1.00, 1.05, 1.45, 1.60])


def make_customers(rng: np.random.Generator, n: int) -> pd.DataFrame:
    days = (END - START).days - 14
    # Acquisition grows over time: later sign-up dates are more likely.
    signup_offset = (rng.beta(1.3, 1.0, n) * days).astype(int)
    seg_names = list(SEGMENTS)
    seg_p = [SEGMENTS[s][0] for s in seg_names]
    channel = rng.choice(list(CHANNELS), n, p=list(CHANNELS.values()))
    segment = rng.choice(seg_names, n, p=seg_p)
    # Referral and email customers are a bit more loyal than paid ones.
    upgrade = (np.isin(channel, ["referral", "email"])) & (rng.random(n) < 0.25)
    segment = np.where(upgrade & (segment == "occasional"), "regular", segment)
    return pd.DataFrame(
        {
            "customer_id": np.arange(10001, 10001 + n),
            "signup_date": START + pd.to_timedelta(signup_offset, unit="D"),
            "country": rng.choice(list(COUNTRIES), n, p=list(COUNTRIES.values())),
            "acquisition_channel": channel,
            "birth_year": rng.integers(1955, 2007, n),
            "latent_segment": segment,
        }
    )


def make_products(rng: np.random.Generator) -> pd.DataFrame:
    rows = []
    pid = 1
    for category, (count, median_price, margin) in CATEGORIES.items():
        prices = np.round(rng.lognormal(np.log(median_price), 0.5, count), 2)
        for price in prices:
            unit_margin = float(np.clip(rng.normal(margin, 0.05), 0.05, 0.8))
            rows.append(
                {
                    "product_id": f"P{pid:04d}",
                    "product_name": f"{category.split()[0]} item {pid:04d}",
                    "category": category,
                    "unit_price": float(price),
                    "unit_cost": round(float(price) * (1 - unit_margin), 2),
                }
            )
            pid += 1
    return pd.DataFrame(rows)


def make_orders(rng: np.random.Generator, customers: pd.DataFrame, products: pd.DataFrame) -> pd.DataFrame:
    """One row per order line."""
    popularity = rng.lognormal(0.0, 1.0, len(products))
    popularity /= popularity.sum()
    product_idx = np.arange(len(products))
    # Every product has one "goes well with" partner, which is added to the
    # basket 30 % of the time. This is the signal the basket analysis finds.
    partner = rng.permutation(product_idx)
    lines = []
    order_no = 500000
    for cust in customers.itertuples(index=False):
        _, yearly_rate, mean_life = SEGMENTS[cust.latent_segment]
        active_until = min(cust.signup_date + pd.Timedelta(days=rng.exponential(mean_life)), END)
        # First order happens at sign-up; later ones follow a Poisson process.
        day = cust.signup_date
        while day <= active_until:
            # Thinning: accept the order with the month's seasonal weight.
            if day == cust.signup_date or rng.random() < SEASONALITY[day.month - 1] / SEASONALITY.max():
                order_no += 1
                n_lines = 1 + rng.poisson(0.9)
                chosen = rng.choice(product_idx, size=min(n_lines, 6), replace=False, p=popularity)
                if rng.random() < 0.30 and partner[chosen[0]] not in chosen:
                    chosen = np.append(chosen, partner[chosen[0]])
                promo = day.month == 11 and day.day >= 20
                order_ts = day + pd.Timedelta(minutes=int(rng.integers(0, 1440)))
                for idx in chosen:
                    discount = rng.choice(
                        [0.0, 0.10, 0.20], p=[0.55, 0.25, 0.20] if promo else [0.85, 0.10, 0.05]
                    )
                    lines.append(
                        (
                            f"O{order_no}",
                            order_ts,
                            cust.customer_id,
                            products.at[idx, "product_id"],
                            int(1 + rng.poisson(0.4)),
                            products.at[idx, "unit_price"],
                            float(discount),
                        )
                    )
            gap = rng.exponential(365.0 / (yearly_rate * SEASONALITY.max() / SEASONALITY.mean()))
            day = day + pd.Timedelta(days=max(1.0, gap))
    cols = ["order_id", "order_ts", "customer_id", "product_id", "quantity", "unit_price", "discount_pct"]
    return pd.DataFrame(lines, columns=cols).sort_values("order_ts", ignore_index=True)


def add_defects(
    rng: np.random.Generator, customers: pd.DataFrame, products: pd.DataFrame, orders: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Inject the problems the staging layer has to detect and repair."""
    customers = customers.drop(columns="latent_segment").copy()
    customers["country"] = customers["country"].astype(object)
    mask = rng.random(len(customers)) < 0.03
    customers.loc[mask, "country"] = customers.loc[mask, "country"].str.lower() + " "
    customers.loc[rng.random(len(customers)) < 0.02, "country"] = None
    customers.loc[rng.random(len(customers)) < 0.01, "birth_year"] = 1900  # placeholder value

    products = products.copy()
    mask = rng.random(len(products)) < 0.08
    products.loc[mask, "category"] = products.loc[mask, "category"].str.upper()

    orders = orders.copy()
    orders["customer_id"] = orders["customer_id"].astype("Int64")
    orders.loc[rng.random(len(orders)) < 0.004, "customer_id"] = pd.NA  # guest / lost key
    orders.loc[rng.random(len(orders)) < 0.003, "quantity"] = 0  # cancelled line
    orders.loc[rng.random(len(orders)) < 0.002, "quantity"] *= -1  # sign error
    dupes = orders.sample(frac=0.01, random_state=int(rng.integers(1_000_000)))  # double export
    orders = pd.concat([orders, dupes]).sort_values("order_ts", kind="stable", ignore_index=True)
    return customers, products, orders


def generate(out_dir: Path, seed: int = 42, n_customers: int = 5000) -> dict[str, int]:
    rng = np.random.default_rng(seed)
    customers = make_customers(rng, n_customers)
    products = make_products(rng)
    orders = make_orders(rng, customers, products)
    customers, products, orders = add_defects(rng, customers, products, orders)

    out_dir.mkdir(parents=True, exist_ok=True)
    customers.to_csv(out_dir / "customers.csv", index=False, date_format="%Y-%m-%d")
    products.to_csv(out_dir / "products.csv", index=False)
    orders.to_csv(out_dir / "order_lines.csv", index=False, date_format="%Y-%m-%d %H:%M:%S")
    return {"customers": len(customers), "products": len(products), "order_lines": len(orders)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=Path("data/raw"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--customers", type=int, default=5000)
    args = parser.parse_args()
    for name, rows in generate(args.out, args.seed, args.customers).items():
        print(f"{name:12s} {rows:>7,d} rows")
