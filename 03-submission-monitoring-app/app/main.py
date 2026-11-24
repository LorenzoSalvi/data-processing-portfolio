"""NiceGUI app: survey submission monitoring (port of an R/Shiny app)."""

from __future__ import annotations

import math
from datetime import date

from nicegui import ui

from gauges import gauge, gauge_without_target, progress_bar
from logic import (
    COL_OVERALL_REACHED,
    COL_TARGET_REACHED,
    COL_TARGET_TO_REACH,
    GAUGE_ONLY_CLUSTERS,
    MonitoringResult,
    ProcessingError,
    TOTALS_TO_SHOW,
    monitoring_excel,
    process,
)

TITLE = "Hello, here is your monitoring app"


@ui.page("/")
def main_page() -> None:
    uploaded_files: dict[str, bytes | None] = {"excel": None, "csv1": None, "csv2": None}
    result_state: dict[str, MonitoringResult | None] = {"value": None}

    def handle_upload(key: str, label: str):
        async def handler(e) -> None:
            uploaded_files[key] = await e.file.read()
            ui.notify(f"{label}: uploaded '{e.file.name}'", type="positive")
        return handler

    @ui.refreshable
    def results_area() -> None:
        result = result_state["value"]
        if result is None:
            ui.label("Upload the three files and press Run to see the results.").classes(
                "text-gray-500"
            )
            return

        with ui.card().classes("w-full"):
            ui.label("Totals: sent and drafts").classes("text-lg font-semibold mb-2")
            for totals_row in TOTALS_TO_SHOW:
                with ui.row().classes("w-full gap-4"):
                    for key, label in totals_row:
                        with ui.card().classes("flex-1 items-center"):
                            ui.label(label).classes("text-sm text-gray-600 text-center")
                            ui.label(str(result.totals[key])).classes("text-3xl font-bold")

        with ui.card().classes("w-full"):
            ui.label("Target monitoring").classes("text-lg font-semibold mb-2")
            # explicit headerName: otherwise AG Grid rewrites the titles in title case
            columns = [{"field": c, "headerName": c} for c in result.target.columns]
            ui.aggrid.from_pandas(result.target, options={"columnDefs": columns}).classes(
                "w-full h-80"
            )

        with ui.card().classes("w-full"):
            ui.label("Progress towards target").classes("text-lg font-semibold mb-2")
            to_show = result.target[
                result.target[COL_TARGET_TO_REACH].notna()
                | result.target["Cluster"].isin(GAUGE_ONLY_CLUSTERS)
            ]
            if to_show.empty:
                ui.label("No cluster with a defined target.")
            else:
                with ui.row().classes("gap-4"):
                    for _, row in to_show.iterrows():
                        with ui.column().classes("items-center w-64"):
                            ui.label(str(row["Cluster"])).classes(
                                "font-semibold text-center"
                            )
                            if math.isnan(row[COL_TARGET_TO_REACH]):
                                ui.plotly(
                                    gauge_without_target(row[COL_OVERALL_REACHED])
                                ).classes("w-64 h-44")
                                continue
                            fig = gauge(
                                row[COL_OVERALL_REACHED], row[COL_TARGET_TO_REACH]
                            )
                            ui.plotly(fig).classes("w-64 h-44")

                            ui.label("Progress towards target (red line = 100%)").classes(
                                "text-xs text-gray-500"
                            )
                            progress = row[COL_TARGET_REACHED]
                            if math.isfinite(progress):
                                ui.plotly(progress_bar(progress)).classes(
                                    "w-64 h-[70px]"
                                )
                            else:
                                ui.label("cannot be calculated").classes("text-xs text-gray-500")

    def on_run() -> None:
        if not all(uploaded_files.values()):
            ui.notify("Upload all three files before running.", type="warning")
            return
        try:
            result_state["value"] = process(
                uploaded_files["excel"], uploaded_files["csv1"], uploaded_files["csv2"]
            )
            results_area.refresh()
            ui.notify("Processing completed.", type="positive")
        except ProcessingError as e:
            ui.notify(str(e), type="negative")
        except Exception as e:  # noqa: BLE001 - shown to the user, as in the R app
            ui.notify(f"Error during processing: {e}", type="negative")

    def on_download() -> None:
        result = result_state["value"]
        if result is None:
            ui.notify("Run the processing first.", type="warning")
            return
        content = monitoring_excel(result)
        file_name = f"{date.today():%Y-%m-%d}_survey_monitoring.xlsx"
        ui.download(content, file_name)

    with ui.header().classes("items-center"):
        ui.label(TITLE).classes("text-lg font-bold")

    with ui.row().classes("w-full no-wrap items-start q-pa-md gap-6"):
        with ui.column().classes("w-80 gap-3"):
            ui.upload(
                label="Upload the registry Excel file",
                auto_upload=True,
                max_files=1,
                on_upload=handle_upload("excel", "Registry Excel file"),
            ).props("accept=.xlsx,.xls").classes("w-full")

            ui.upload(
                label="Upload report 1 (CSV)",
                auto_upload=True,
                max_files=1,
                on_upload=handle_upload("csv1", "Report 1"),
            ).props("accept=.csv").classes("w-full")

            ui.upload(
                label="Upload report 2 (CSV)",
                auto_upload=True,
                max_files=1,
                on_upload=handle_upload("csv2", "Report 2"),
            ).props("accept=.csv").classes("w-full")

            ui.button("Run", on_click=on_run).classes("w-full").props("color=primary")
            ui.separator()
            ui.button(
                "Download the full monitoring Excel", on_click=on_download
            ).classes("w-full").props("outline")

        with ui.column().classes("flex-grow gap-4"):
            results_area()


if __name__ in {"__main__", "__mp_main__"}:
    # the native window (pywebview) blocks downloads by default: they must be
    # enabled explicitly, otherwise the download button does nothing
    import webview
    webview.settings["ALLOW_DOWNLOADS"] = True

    ui.run(title="Survey monitoring", native=True, window_size=(1280, 900), reload=False)
