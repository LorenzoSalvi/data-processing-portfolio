"""Data processing logic, Python port of survey_monitoring.R.

No NiceGUI dependency in here: only pandas/openpyxl, so the logic stays
testable and reusable independently of the user interface.
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO

import pandas as pd

# --- targets by cluster (same logic as survey_monitoring.R; placeholder values) ---

TARGET_REGIONAL_BODIES = 85
TARGET_HEALTH_AUTHORITIES = 88
TARGET_NATIONAL_LARGE = 65
TARGET_NATIONAL_SMALL = 45
TARGET_LARGE_CITIES = 80
TARGET_MEDIUM_CITIES = 75
TARGET_SMALL_CITIES = 55
TARGET_SCHOOLS = 35
TARGET_UNIVERSITIES = 60

CLUSTER_LEVELS = [
    "Large cities",
    "Medium cities",
    "Small cities",
    "Micro cities",
    "Regional bodies",
    "Health authorities",
    "National agencies (large)",
    "National agencies (small)",
    "Schools",
    "Universities",
    "Other",
]

_TARGET_BY_CLUSTER = {
    "Large cities": TARGET_LARGE_CITIES,
    "Medium cities": TARGET_MEDIUM_CITIES,
    "Small cities": TARGET_SMALL_CITIES,
    "Regional bodies": TARGET_REGIONAL_BODIES,
    "Health authorities": TARGET_HEALTH_AUTHORITIES,
    "National agencies (large)": TARGET_NATIONAL_LARGE,
    "National agencies (small)": TARGET_NATIONAL_SMALL,
    "Schools": TARGET_SCHOOLS,
    "Universities": TARGET_UNIVERSITIES,
}


# names and order of the columns in the "Target monitoring" and "Area monitoring" sheets
COL_TARGET_TO_REACH = "Target - % to reach"
COL_TARGET_REACHED = "Target - % reached"
COL_OVERALL_REACHED = "Overall - % reached"

_OUTPUT_RENAME = {
    "Target total": "Target - total to send",
    "Progress percentage": COL_TARGET_REACHED,
    "Target percentage": COL_TARGET_TO_REACH,
    "Total": "Overall - total to send",
    "Percentage sent": COL_OVERALL_REACHED,
}

_OUTPUT_COLUMNS = [
    "Total sent",
    "Total drafts",
    "Target - total to send",
    COL_TARGET_REACHED,
    COL_TARGET_TO_REACH,
    "Overall - total to send",
    COL_OVERALL_REACHED,
]


def target_for_cluster(cluster: str) -> float:
    return _TARGET_BY_CLUSTER.get(cluster, float("nan"))


# October clusters; "Other" belongs neither to July nor to October
OCTOBER_CLUSTERS = ["Schools", "Universities"]
NOT_JULY_CLUSTERS = OCTOBER_CLUSTERS + ["Other"]

# clusters without a target that still show the gauge (gauge only, no progress bar)
GAUGE_ONLY_CLUSTERS = ["Micro cities"]

# totals shown at the top: first the row of sent surveys, then the row of drafts
TOTALS_TO_SHOW = [
    [
        ("all_sent", "Total sent - all clusters"),
        ("july_sent", "Total sent - July cluster"),
        ("october_sent", "Total sent - October cluster"),
    ],
    [
        ("all_drafts", "Total drafts - all clusters"),
        ("july_drafts", "Total drafts - July cluster"),
        ("october_drafts", "Total drafts - October cluster"),
    ],
]


class ProcessingError(Exception):
    """Application error that can be shown directly to the user in the UI."""


@dataclass
class MonitoringResult:
    detailed: pd.DataFrame  # sheet "Detailed monitoring"
    target: pd.DataFrame  # sheet "Target monitoring"
    areas: pd.DataFrame  # sheet "Area monitoring"
    totals: dict[str, int]  # keys of TOTALS_TO_SHOW


def _read_registry(file_bytes: bytes) -> pd.DataFrame:
    exemption_col = "Is the body exempt from the survey?"
    required = [
        "Code", "Organization name", "Cluster", "Account Manager", "Technical support", "Area",
        "Invitation sent on", "Did the body receive the invitation? (YES/NO)",
        "NOTES on the body's survey completion", exemption_col,
    ]
    df = pd.read_excel(BytesIO(file_bytes))
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ProcessingError(
            f"Missing columns in the registry Excel file: {', '.join(missing)}"
        )

    # bodies exempt from the survey are moved to the "Other" cluster
    exempt = df[exemption_col].astype(str).str.contains(
        "YES|Yes|yes", regex=True, na=False
    )
    df.loc[exempt, "Cluster"] = "Other"

    df = df.rename(columns={
        "Code": "Org code",
        "Organization name": "Organization",
        "Account Manager": "Account manager",
        "Did the body receive the invitation? (YES/NO)": "Invitation received",
        "NOTES on the body's survey completion": "Registry notes",
    })
    return df[[
        "Org code", "Organization", "Cluster", "Account manager", "Technical support", "Area",
        "Invitation sent on", "Invitation received", "Registry notes",
    ]]


def _read_report1(file_bytes: bytes) -> pd.DataFrame:
    required = ["Account: Org code", "Status"]
    df = pd.read_csv(BytesIO(file_bytes), sep=";", encoding="latin1")
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ProcessingError(
            f"Missing columns in report 1: {', '.join(missing)}"
        )

    df = df.rename(columns={"Account: Org code": "Org code"})
    df = df[["Org code", "Status"]]

    # a body may have more than one record: keep the most advanced status
    priority = pd.CategoricalDtype(
        categories=["Not started", "Draft", "Sent"], ordered=True
    )
    df["Status"] = df["Status"].astype(priority)
    df = df.sort_values("Status", ascending=False)
    df = df.drop_duplicates(subset="Org code", keep="first")
    df["Status"] = df["Status"].astype(str)
    return df


def _read_report2(file_bytes: bytes) -> pd.DataFrame:
    required = ["Date", "Organization name", "Meeting title", "Comments"]
    df = pd.read_csv(BytesIO(file_bytes), sep=";", encoding="latin1")
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ProcessingError(
            f"Missing columns in report 2: {', '.join(missing)}"
        )

    df = df.rename(columns={"Organization name": "Organization"})
    df["Last contact date"] = pd.to_datetime(df["Date"], dayfirst=True, errors="coerce")
    df = df[["Last contact date", "Organization", "Meeting title", "Comments"]]

    # keep only the most recent contact with each body
    df = df.sort_values("Last contact date", ascending=False)
    df = df.drop_duplicates(subset="Organization", keep="first")
    return df


def _aggregate(df: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    tmp = df.copy()
    tmp["Sent"] = (tmp["Status"] == "Sent").astype(int)
    tmp["Drafts"] = (tmp["Status"] == "Draft").astype(int)
    out = (
        tmp.groupby(group_cols, as_index=False)
           .agg(**{
               "Total sent": ("Sent", "sum"),
               "Total drafts": ("Drafts", "sum"),
               "Total": ("Sent", "size"),
           })
    )
    out["Percentage sent"] = (out["Total sent"] / out["Total"] * 100).round(2)
    out["Target percentage"] = out["Cluster"].apply(target_for_cluster)
    out["Target total"] = (out["Target percentage"] / 100 * out["Total"]).round(2)
    out["Progress percentage"] = (
        out["Total sent"] / out["Target total"] * 100
    ).round(2)
    return out


def _sort_by_cluster(df: pd.DataFrame, other_columns: list[str] | None = None) -> pd.DataFrame:
    order = other_columns or []
    cat = pd.Categorical(df["Cluster"], categories=CLUSTER_LEVELS, ordered=True)
    df = df.assign(Cluster=cat)
    df = df.sort_values(order + ["Cluster"]).reset_index(drop=True)
    df["Cluster"] = df["Cluster"].astype(str)
    return df


def _rename_and_order(df: pd.DataFrame, first_columns: list[str]) -> pd.DataFrame:
    df = df.rename(columns=_OUTPUT_RENAME)
    return df[first_columns + _OUTPUT_COLUMNS]


def process(excel_bytes: bytes, csv1_bytes: bytes, csv2_bytes: bytes) -> MonitoringResult:
    registry = _read_registry(excel_bytes)
    report1 = _read_report1(csv1_bytes)
    report2 = _read_report2(csv2_bytes)

    # bodies with no record in report 1 never opened the survey
    detailed = (
        registry
        .merge(report1, on="Org code", how="left")
        .merge(report2, on="Organization", how="left")
    )
    detailed["Status"] = detailed["Status"].fillna("Not opened")

    target = _aggregate(detailed, ["Cluster"])
    target = _sort_by_cluster(target)
    target = _rename_and_order(target, ["Cluster"])

    # national agencies are not assigned to areas, so they are excluded here
    areas = detailed[
        ~detailed["Cluster"].astype(str).str.contains("National agencies", na=False)
    ]
    areas = _aggregate(areas, ["Area", "Cluster"])
    areas = areas.dropna(subset=["Area"])
    areas = _sort_by_cluster(areas, other_columns=["Area"])
    areas = _rename_and_order(areas, ["Area", "Cluster"])

    july = target[~target["Cluster"].isin(NOT_JULY_CLUSTERS)]
    october = target[target["Cluster"].isin(OCTOBER_CLUSTERS)]
    totals = {
        "all_sent": int(target["Total sent"].sum()),
        "july_sent": int(july["Total sent"].sum()),
        "october_sent": int(october["Total sent"].sum()),
        "all_drafts": int(target["Total drafts"].sum()),
        "july_drafts": int(july["Total drafts"].sum()),
        "october_drafts": int(october["Total drafts"].sum()),
    }

    return MonitoringResult(
        detailed=detailed, target=target, areas=areas, totals=totals
    )


def _autofit_columns(worksheet) -> None:
    for column in worksheet.columns:
        length = max(
            (len(str(cell.value)) if cell.value is not None else 0) for cell in column
        )
        letter = column[0].column_letter
        worksheet.column_dimensions[letter].width = min(length + 2, 60)


def monitoring_excel(result: MonitoringResult) -> bytes:
    buffer = BytesIO()
    with pd.ExcelWriter(buffer, engine="openpyxl") as writer:
        result.detailed.to_excel(writer, sheet_name="Detailed monitoring", index=False)
        result.target.to_excel(writer, sheet_name="Target monitoring", index=False)
        result.areas.to_excel(writer, sheet_name="Area monitoring", index=False)
        for sheet in writer.sheets.values():
            _autofit_columns(sheet)
    return buffer.getvalue()
