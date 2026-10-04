#!/usr/bin/env python3
"""
Build the offline product database for DigiFinder. Run once before the event, on a laptop.

Inputs
  - Open Food Facts Parquet export (downloaded from Hugging Face automatically, or pass --off)
  - aisle_map.json: hand-edited map of store aisles -> Open Food Facts category tags
  - optional: USDA FoodData Central "Branded Foods" CSV folder (--usda), public domain, US products

Outputs (in --out, default ./build), copy both into the app's Resources/ folder
  - products.sqlite   barcode -> name, brand, quantity, aisle; plus full-text search over brand/name
  - categories.json   aisles with productWords filled in automatically (top brands + keywords) + offTags

Usage
  pip install duckdb huggingface_hub
  python build_product_db.py --aisle-map aisle_map.json
  python build_product_db.py --off food.parquet --usda ./FoodData_Central_branded_food_csv \
      --aisle-map aisle_map.json --check demo_barcodes.txt

Licenses
  Open Food Facts data is under the Open Database License (ODbL): credit Open Food Facts in the app,
  and share any changes to the database itself under the same license.
  USDA FoodData Central is public domain.
"""
import argparse
import json
import os
import re
import sqlite3
import sys
import unicodedata
from collections import Counter

import duckdb

COUNTRIES = ["en:canada", "en:united-states"]
HF_REPO = "openfoodfacts/product-database"

STOPWORDS = {
    "the", "and", "with", "for", "from", "of", "in", "a", "an", "de", "la", "le", "et", "du", "des",
    "original", "classic", "new", "flavour", "flavor", "flavored", "flavoured", "style", "brand",
    "pack", "size", "family", "value", "organic", "natural", "premium", "product", "food", "foods",
}


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def normalize(text):
    """Lowercase, strip accents, keep letters/digits/spaces. Must match the app's normalization."""
    if not text:
        return ""
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^a-z0-9 ]+", " ", text.lower())
    return re.sub(r"\s+", " ", text).strip()


def tidy(text):
    """Trim, and convert ALL-CAPS names (common in USDA data) to title case."""
    text = (text or "").strip()
    return text.title() if text.isupper() else text


def find_off_parquet(path):
    if path:
        return path
    from huggingface_hub import hf_hub_download, list_repo_files
    files = list_repo_files(HF_REPO, repo_type="dataset")
    candidates = [f for f in files if f.endswith(".parquet") and "food" in f.lower() and "beauty" not in f.lower()]
    if not candidates:
        sys.exit("Couldn't find the food Parquet file on Hugging Face. Download it manually and pass --off.")
    name = sorted(candidates, key=len)[0]
    print(f"Downloading {name} from {HF_REPO} (several GB, one time)...")
    return hf_hub_download(HF_REPO, name, repo_type="dataset")


def sql_list(values):
    return "[" + ", ".join("'" + v.replace("'", "''") + "'" for v in values) + "]"


# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------

def load_open_food_facts(con, parquet, countries):
    print("Filtering Open Food Facts to", ", ".join(countries), "...")
    con.execute(f"""
        CREATE TABLE off_raw AS
        SELECT
            CASE WHEN length(code) = 12 THEN '0' || code ELSE code END AS code,
            COALESCE(
                list_filter(product_name, x -> x.lang = 'en')[1].text,
                list_filter(product_name, x -> x.lang = 'main')[1].text
            ) AS name,
            trim(split_part(brands, ',', 1)) AS brand,
            quantity,
            categories_tags AS cats
        FROM read_parquet('{parquet}')
        WHERE list_has_any(countries_tags, {sql_list(countries)})
          AND code IS NOT NULL
          AND regexp_full_match(code, '[0-9]{{8,14}}')
    """)
    con.execute("""
        CREATE TABLE off AS
        SELECT DISTINCT ON (code) * FROM off_raw
        WHERE name IS NOT NULL AND trim(name) <> ''
    """)
    print("  products kept:", con.execute("SELECT count(*) FROM off").fetchone()[0])


def load_aisle_map(con, aisle_map):
    con.execute("CREATE TABLE amap (aisle VARCHAR, tag VARCHAR, prio INTEGER)")
    con.execute("CREATE TABLE umap (aisle VARCHAR, usda_cat VARCHAR, prio INTEGER)")
    for prio, (aisle, spec) in enumerate(aisle_map.items()):
        for tag in spec.get("offTags", []):
            con.execute("INSERT INTO amap VALUES (?, ?, ?)", [aisle, tag, prio])
        for cat in spec.get("usdaCategories", []):
            con.execute("INSERT INTO umap VALUES (?, ?, ?)", [aisle, cat.lower(), prio])


def assign_aisles(con):
    con.execute("""
        CREATE TABLE prod AS
        WITH tagged AS (
            SELECT o.code, a.aisle, a.prio
            FROM off o, unnest(o.cats) AS t(tag)
            JOIN amap a ON a.tag = t.tag
        ),
        best AS (
            SELECT code, arg_min(aisle, prio) AS aisle FROM tagged GROUP BY code
        )
        SELECT o.code, o.name, o.brand, o.quantity, b.aisle
        FROM off o LEFT JOIN best b USING (code)
    """)


def merge_usda(con, usda_dir):
    branded = os.path.join(usda_dir, "branded_food.csv")
    food = os.path.join(usda_dir, "food.csv")
    if not (os.path.exists(branded) and os.path.exists(food)):
        sys.exit(f"--usda folder must contain branded_food.csv and food.csv: {usda_dir}")
    print("Merging USDA Branded Foods (only barcodes Open Food Facts doesn't have)...")
    con.execute(f"""
        CREATE TABLE usda AS
        SELECT
            CASE WHEN length(b.gtin_upc) = 12 THEN '0' || b.gtin_upc ELSE b.gtin_upc END AS code,
            f.description AS name,
            b.brand_owner AS brand,
            NULL::VARCHAR AS quantity,
            lower(b.branded_food_category) AS usda_cat
        FROM read_csv('{branded}', all_varchar = true, header = true) b
        JOIN read_csv('{food}', all_varchar = true, header = true) f USING (fdc_id)
        WHERE regexp_full_match(b.gtin_upc, '[0-9]{{8,14}}')
          AND f.description IS NOT NULL
    """)
    con.execute("""
        INSERT INTO prod
        SELECT DISTINCT ON (u.code)
            u.code, u.name, u.brand, u.quantity,
            (SELECT m.aisle FROM umap m WHERE m.usda_cat = u.usda_cat ORDER BY m.prio LIMIT 1)
        FROM usda u
        WHERE u.code NOT IN (SELECT code FROM prod)
    """)
    print("  total products now:", con.execute("SELECT count(*) FROM prod").fetchone()[0])


def write_sqlite(con, path, with_fts):
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE products (
            code     TEXT PRIMARY KEY,
            name     TEXT NOT NULL,
            brand    TEXT,
            quantity TEXT,
            aisle    TEXT,
            search   TEXT NOT NULL
        );
        CREATE INDEX idx_products_aisle ON products(aisle);
    """)
    cursor = con.execute("SELECT code, name, brand, quantity, aisle FROM prod")
    total = 0
    while True:
        rows = cursor.fetchmany(50_000)
        if not rows:
            break
        db.executemany(
            "INSERT OR IGNORE INTO products VALUES (?, ?, ?, ?, ?, ?)",
            [(c, tidy(n), tidy(b) or None, q, a, normalize(f"{b or ''} {n} {q or ''}"))
             for c, n, b, q, a in rows],
        )
        total += len(rows)
    if with_fts:
        db.executescript("""
            CREATE VIRTUAL TABLE products_fts USING fts5(search, content='products', content_rowid='rowid');
            INSERT INTO products_fts(products_fts) VALUES ('rebuild');
        """)
    db.commit()
    db.execute("VACUUM")
    db.close()
    size_mb = os.path.getsize(path) / 1_000_000
    print(f"Wrote {path}: {total:,} rows, {size_mb:.1f} MB")
    if size_mb > 60:
        print("  Large file. To shrink: --aisles-only, --require-brand, or --no-fts.")


def write_categories(con, aisle_map, path, top_brands, top_keywords):
    out = {}
    for aisle, spec in aisle_map.items():
        rows = con.execute("SELECT name, brand FROM prod WHERE aisle = ?", [aisle]).fetchall()
        brands = Counter(normalize(b) for _, b in rows if b and normalize(b))
        brand_tokens = {t for b in brands for t in b.split()}
        words = Counter(
            t for n, _ in rows for t in normalize(n).split()
            if len(t) >= 3 and not t.isdigit() and t not in STOPWORDS and t not in brand_tokens
        )
        product_words = [b for b, _ in brands.most_common(top_brands)] + \
                        [w for w, _ in words.most_common(top_keywords)]
        out[aisle] = {
            "aisleWords": spec.get("aisleWords", [aisle]),
            "productWords": spec.get("extraWords", []) + product_words,
            "visualClasses": spec.get("visualClasses", []),   # YOLO Open Images classes, for sections with no text
            "adjacent": spec.get("adjacent", []),
            "offTags": spec.get("offTags", []),                 # lets the app map online Open Food Facts hits to an aisle
        }
        print(f"  {aisle}: {len(rows):,} products, e.g. {', '.join(product_words[:6])}")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {path}")


def check_barcodes(path, db_path):
    with open(path) as f:
        codes = [c.strip() for c in re.split(r"[\s,]+", f.read()) if c.strip()]
    db = sqlite3.connect(db_path)
    print("Demo product check:")
    missing = 0
    for raw in codes:
        code = "0" + raw if len(raw) == 12 else raw
        row = db.execute("SELECT brand, name, quantity, aisle FROM products WHERE code = ?", [code]).fetchone()
        if row:
            print(f"  ✓ {raw}: {row[0] or ''} {row[1]} {row[2] or ''} [{row[3] or 'no aisle'}]")
        else:
            missing += 1
            print(f"  ✗ {raw}: not found. Add it to products.json in the app or to Open Food Facts.")
    print(f"  {len(codes) - missing}/{len(codes)} found")


# ---------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Build DigiFinder's offline product database.")
    ap.add_argument("--off", help="Path to the Open Food Facts food Parquet file (downloads if omitted)")
    ap.add_argument("--usda", help="Folder with USDA Branded Foods CSVs (branded_food.csv, food.csv)")
    ap.add_argument("--aisle-map", required=True, help="aisle_map.json")
    ap.add_argument("--out", default="build", help="Output folder (default: build)")
    ap.add_argument("--countries", default=",".join(COUNTRIES), help="Open Food Facts country tags")
    ap.add_argument("--require-brand", action="store_true", help="Drop products with no brand")
    ap.add_argument("--aisles-only", action="store_true",
                    help="Keep only products that map to an aisle in aisle_map.json (much smaller file)")
    ap.add_argument("--no-fts", action="store_true", help="Skip full-text search index (smaller file)")
    ap.add_argument("--top-brands", type=int, default=15)
    ap.add_argument("--top-keywords", type=int, default=10)
    ap.add_argument("--check", help="File of demo barcodes to verify after building")
    args = ap.parse_args()

    with open(args.aisle_map) as f:
        aisle_map = json.load(f)
    os.makedirs(args.out, exist_ok=True)

    con = duckdb.connect()
    load_open_food_facts(con, find_off_parquet(args.off), args.countries.split(","))
    load_aisle_map(con, aisle_map)
    assign_aisles(con)
    if args.usda:
        merge_usda(con, args.usda)
    if args.require_brand:
        con.execute("DELETE FROM prod WHERE brand IS NULL OR trim(brand) = ''")
    if args.aisles_only:
        con.execute("DELETE FROM prod WHERE aisle IS NULL")

    db_path = os.path.join(args.out, "products.sqlite")
    write_sqlite(con, db_path, with_fts=not args.no_fts)
    write_categories(con, aisle_map, os.path.join(args.out, "categories.json"),
                     args.top_brands, args.top_keywords)
    if args.check:
        check_barcodes(args.check, db_path)


if __name__ == "__main__":
    main()
