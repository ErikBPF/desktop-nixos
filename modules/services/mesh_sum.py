# mesh_sum — add a saved bed_mesh profile to the ACTIVE mesh and apply it.
#
# NOTE: the config section is [mesh_sum], NOT [bed_mesh_sum] — Klipper's bed_mesh
# ProfileManager scans every section prefixed "bed_mesh" and does name.split(' ')[1]
# to read the profile name, so a [bed_mesh_sum] section crashes klippy with an
# IndexError on connect. Keep this extra's section name clear of that prefix.
#
# Enables a "live calibrate + fixed correction" workflow on archinaut (BIQU B1):
# the BTT Eddy coil does not represent the nozzle across X (see the klipper-biqu
# first-layer-planarity-plan), so a raw per-print calibration bakes in a wrong
# left-high map. Instead START_PRINT calibrates a fresh (zero-referenced, hence
# small/centered) mesh, then does:
#
#     BED_MESH_SUM PROFILE=compensate
#
# which sums the live mesh with the hand-authored `compensate` tilt profile and
# installs the result — tracking real day-to-day bed shape while keeping the
# fixed coil->nozzle correction. Enable with a bare `[mesh_sum]` config section.
# Requires [bed_mesh]; grids must match (same x_count/y_count).


class BedMeshSum:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object("gcode")
        self.gcode.register_command(
            "BED_MESH_SUM",
            self.cmd_BED_MESH_SUM,
            desc=self.cmd_BED_MESH_SUM_help,
        )

    cmd_BED_MESH_SUM_help = (
        "Add a saved bed_mesh PROFILE=<name> to the active mesh and apply it"
    )

    def cmd_BED_MESH_SUM(self, gcmd):
        bed_mesh = self.printer.lookup_object("bed_mesh")
        active = bed_mesh.get_mesh()
        if active is None:
            raise gcmd.error(
                "BED_MESH_SUM: no active mesh — run BED_MESH_CALIBRATE first"
            )
        prof_name = gcmd.get("PROFILE")
        profiles = bed_mesh.pmgr.get_profiles()
        if prof_name not in profiles:
            raise gcmd.error("BED_MESH_SUM: unknown profile '%s'" % (prof_name,))
        add = profiles[prof_name]["points"]
        base = active.get_probed_matrix()
        params = active.get_mesh_params()
        if base is None:
            raise gcmd.error("BED_MESH_SUM: active mesh has no probed matrix")
        if len(base) != len(add) or any(
            len(base[y]) != len(add[y]) for y in range(len(base))
        ):
            raise gcmd.error(
                "BED_MESH_SUM: grid mismatch — active %dx%d vs profile '%s' %dx%d"
                % (
                    len(base),
                    len(base[0]) if base else 0,
                    prof_name,
                    len(add),
                    len(add[0]) if add else 0,
                )
            )
        summed = [
            [base[y][x] + add[y][x] for x in range(len(base[y]))]
            for y in range(len(base))
        ]
        # ZMesh is not exported by name; take it off the live mesh instance.
        zmesh_cls = type(active)
        new_name = "sum(%s+%s)" % (active.get_profile_name(), prof_name)
        new_mesh = zmesh_cls(params, new_name)
        try:
            new_mesh.build_mesh(summed)
        except Exception as e:
            raise gcmd.error("BED_MESH_SUM: build failed: %s" % (e,))
        bed_mesh.set_mesh(new_mesh)
        gcmd.respond_info(
            "BED_MESH_SUM: added profile '%s' to the active mesh" % (prof_name,)
        )


def load_config(config):
    return BedMeshSum(config)
