"""Run with PERSISTED_RTP pointing at the pinned persisted.nvim package."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="nvim-sessions-") as temporary:
        work = Path(temporary)
        state = work / "state"
        repo = work / "repo"
        other = work / "other"
        repo.mkdir()
        other.mkdir()
        source = repo / "source.py"
        source.write_text("original\n")
        init = work / "init.lua"
        init.write_text(
            'vim.opt.hidden = true\n'
            'if vim.env.PERSISTED_RTP then vim.opt.rtp:prepend(vim.env.PERSISTED_RTP) end\n'
            f'local config = {json.dumps(str(root / "modules/dev/nvim-sessions.lua"))}\n'
            'if vim.fn.filereadable(config) == 1 then dofile(config) end\n'
        )
        env = dict(os.environ, XDG_STATE_HOME=str(state), XDG_DATA_HOME=str(work / "data"),
                   XDG_CONFIG_HOME=str(work / "config"), XDG_CACHE_HOME=str(work / "cache"))
        (work / "data/nvim").mkdir(parents=True)

        def run(lua, cwd=repo, args=()):
            script = work / "action.lua"
            script.write_text(lua)
            result = subprocess.run(
                [os.environ.get("NVIM", "nvim"), "--headless", "-u", os.environ.get("NVIM_INIT", str(init)), "-i", "NONE",
                 "--cmd", "let g:loaded_spellfile_plugin = 1",
                 "-c", 'lua vim.defer_fn(function() local ok, err = pcall(dofile, vim.env.NVIM_TEST_SCRIPT); '
                 'if not ok then io.stderr:write(tostring(err)); vim.cmd("cquit") end end, 100)', *args],
                env=dict(env, NVIM_TEST_SCRIPT=str(script)), cwd=cwd,
                text=True, capture_output=True, timeout=20,
            )
            assert result.returncode == 0, result.stdout + result.stderr
            assert "Error detected" not in result.stderr, result.stderr

        run('''
vim.cmd("edit source.py")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {"unsaved source"})
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {"first scratch", "Unicode: café"})
vim.cmd("vnew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {"second scratch"})
vim.cmd("qa!")
''')
        assert source.read_text() == "original\n", "scratch autosave wrote a source file"
        report = work / "buffers.json"
        inspect = f'''
local result = {{buffers = {{}}, windows = #vim.api.nvim_list_wins()}}
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].buflisted then
    vim.fn.bufload(buf)
    table.insert(result.buffers, {{name = vim.api.nvim_buf_get_name(buf),
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)}})
  end
end
vim.fn.writefile({{vim.json.encode(result)}}, {json.dumps(str(report))})
vim.cmd("qa")
'''
        run(inspect)
        restored = json.loads(report.read_text())
        contents = [buffer["lines"] for buffer in restored["buffers"]]
        assert ["first scratch", "Unicode: café"] in contents, ("hidden scratch text not restored", restored)
        assert ["second scratch"] in contents, "visible scratch text not restored"
        assert ["original"] in contents, "named file not restored from disk"
        assert restored["windows"] == 2, "split layout not restored"
        for buffer in restored["buffers"]:
            path = Path(buffer["name"])
            if path.is_relative_to(state):
                assert path.stat().st_mode & 0o077 == 0, "scratch file is not private"
        run(inspect, cwd=other)
        assert not any(b["lines"] == ["second scratch"] for b in json.loads(report.read_text())["buffers"]), "repo sessions mixed"
        sessions_before = {p: p.read_bytes() for p in state.rglob("*.vim")}
        run('vim.cmd("qa")', args=("source.py",))
        assert all(p.read_bytes() == data for p, data in sessions_before.items()), "file launch overwrote repo session"
        run(inspect, args=(".",))
        assert ["second scratch"] in [b["lines"] for b in json.loads(report.read_text())["buffers"]], "nvim . did not restore session"
        run('vim.cmd("enew"); vim.api.nvim_buf_set_lines(0, 0, -1, false, {"quit without naming"}); vim.cmd("qa")', cwd=other)
        run(inspect, cwd=other)
        assert ["quit without naming"] in [b["lines"] for b in json.loads(report.read_text())["buffers"]], "normal quit lost unnamed buffer"
    print("PASS: restart restores scratch text and layout; repo isolation, file launches, private notes, normal quit")


if __name__ == "__main__":
    main()
