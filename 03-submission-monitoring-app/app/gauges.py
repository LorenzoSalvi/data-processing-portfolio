"""Plotly gauges for the 'Progress towards target' card."""

from __future__ import annotations

import plotly.graph_objects as go

RED = "#c10000"
YELLOW = "#f9b928"
GREEN = "#00891a"

LIGHT_RED = "#f8d6d6"
LIGHT_YELLOW = "#fbeac1"
LIGHT_GREEN = "#c9e8ce"


def bar_colour(value: float, target: float) -> str:
    if value < target / 2:
        return RED
    if value < target:
        return YELLOW
    return GREEN


def progress_colour(progress: float) -> str:
    """Same logic as the gauges, expressed as % of progress towards the target."""
    if progress < 50:
        return RED
    if progress < 100:
        return YELLOW
    return GREEN


def progress_bar(progress: float) -> go.Figure:
    axis_max = max(110, progress * 1.05)
    fig = go.Figure(go.Bar(
        x=[progress],
        y=["progress"],
        orientation="h",
        marker={"color": progress_colour(progress)},
        text=[f"{progress:g}%"],
        textposition="auto",
        hoverinfo="none",
    ))
    fig.update_layout(
        xaxis={"range": [0, axis_max], "ticksuffix": "%", "fixedrange": True},
        yaxis={"visible": False, "fixedrange": True},
        shapes=[
            {"type": "rect", "x0": 0, "x1": axis_max, "y0": 0, "y1": 1, "yref": "paper",
             "fillcolor": "#eeeeee", "line": {"width": 0}, "layer": "below"},
            {"type": "line", "x0": 100, "x1": 100, "y0": 0, "y1": 1, "yref": "paper",
             "line": {"color": "red", "width": 4}},
        ],
        margin={"l": 25, "r": 25, "t": 5, "b": 25},
        bargap=0.15,
        height=70,
    )
    return fig


def gauge(value: float, target: float) -> go.Figure:
    fig = go.Figure(go.Indicator(
        mode="gauge+number",
        value=value,
        number={"suffix": "%"},
        gauge={
            "axis": {"range": [0, 100], "ticksuffix": "%"},
            "bar": {"color": bar_colour(value, target)},
            "bgcolor": "white",
            "borderwidth": 0,
            "steps": [
                {"range": [0, target / 2], "color": LIGHT_RED},
                {"range": [target / 2, target], "color": LIGHT_YELLOW},
                {"range": [target, 100], "color": LIGHT_GREEN},
            ],
            "threshold": {
                "line": {"color": "red", "width": 4},
                "thickness": 0.85,
                "value": target,
            },
        },
    ))
    fig.update_layout(margin={"l": 25, "r": 25, "t": 25, "b": 10}, height=180)
    return fig


def gauge_without_target(value: float) -> go.Figure:
    """Neutral gauge: without a target there are no thresholds and no red/yellow/green."""
    fig = go.Figure(go.Indicator(
        mode="gauge+number",
        value=value,
        number={"suffix": "%"},
        gauge={
            "axis": {"range": [0, 100], "ticksuffix": "%"},
            "bar": {"color": "#4f6d8f"},
            "bgcolor": "white",
            "borderwidth": 0,
            "steps": [{"range": [0, 100], "color": "#e6ebf1"}],
        },
    ))
    fig.update_layout(margin={"l": 25, "r": 25, "t": 25, "b": 10}, height=180)
    return fig
