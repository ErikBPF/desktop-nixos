#!/usr/bin/env python3
"""Discovery advertises the narrow NanoKVM subnet route."""

import pathlib


def test_discovery_advertises_nanokvm_host_route():
    repo = pathlib.Path(__file__).resolve().parents[2]
    config = (repo / "modules/hosts/discovery/networking.nix").read_text()

    assert "192.168.10.4/32" in config
