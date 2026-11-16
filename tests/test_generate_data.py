"""Tests for the data simulator (the warehouse itself is tested in sql/06_tests.sql)."""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data"))
import generate_data  # noqa: E402


@pytest.fixture(scope="module")
def raw(tmp_path_factory: pytest.TempPathFactory) -> dict[str, pd.DataFrame]:
    out = tmp_path_factory.mktemp("raw")
    generate_data.generate(out, seed=7, n_customers=400)
    return {path.stem: pd.read_csv(path) for path in out.glob("*.csv")}


def test_same_seed_gives_identical_files(tmp_path: Path) -> None:
    generate_data.generate(tmp_path / "a", seed=1, n_customers=100)
    generate_data.generate(tmp_path / "b", seed=1, n_customers=100)
    for name in ("customers.csv", "products.csv", "order_lines.csv"):
        assert (tmp_path / "a" / name).read_bytes() == (tmp_path / "b" / name).read_bytes()


def test_every_customer_places_at_least_one_order(raw: dict[str, pd.DataFrame]) -> None:
    ordered = set(raw["order_lines"]["customer_id"].dropna().astype(int))
    missing = set(raw["customers"]["customer_id"]) - ordered
    # A customer can only go missing if all of their lines lost the key (rare defect).
    assert len(missing) <= 0.02 * len(raw["customers"])


def test_orders_reference_existing_products(raw: dict[str, pd.DataFrame]) -> None:
    assert set(raw["order_lines"]["product_id"]) <= set(raw["products"]["product_id"])


def test_an_order_has_one_timestamp_and_one_customer(raw: dict[str, pd.DataFrame]) -> None:
    per_order = raw["order_lines"].groupby("order_id")
    assert per_order["order_ts"].nunique().max() == 1
    assert per_order["customer_id"].nunique().max() <= 1


def test_defects_are_present_so_cleaning_is_exercised(raw: dict[str, pd.DataFrame]) -> None:
    lines, customers, products = raw["order_lines"], raw["customers"], raw["products"]
    assert lines.duplicated().sum() > 0
    assert lines["customer_id"].isna().sum() > 0
    assert (lines["quantity"] <= 0).sum() > 0
    assert customers["country"].isna().sum() > 0
    assert (products["category"] == products["category"].str.upper()).sum() > 0


def test_products_are_sold_above_cost(raw: dict[str, pd.DataFrame]) -> None:
    assert (raw["products"]["unit_cost"] < raw["products"]["unit_price"]).all()
