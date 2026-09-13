local state = vim.fn.stdpath("state")
local scratch_root = state .. "/scratch/"
local scratch_dir = scratch_root .. vim.fn.sha256(vim.fn.getcwd())
local session_dir = state .. "/sessions/"
vim.fn.mkdir(session_dir, "p", 448)
vim.opt.hidden = true

-- Give unnamed notes private backing files so native sessions can restore text.
-- Named source files retain normal explicit-save semantics.
local saving = false
vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost", "ExitPre", "VimLeavePre" }, {
	callback = function()
		if saving then
			return
		end
		saving = true
		local ok, err = pcall(function()
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and vim.bo[buf].modified then
					local name = vim.api.nvim_buf_get_name(buf)
					local fresh = name == ""
					if name == "" then
						vim.fn.mkdir(scratch_dir, "p", 448)
						local fd, path = assert(vim.uv.fs_mkstemp(scratch_dir .. "/note-XXXXXX"))
						assert(vim.uv.fs_close(fd))
						name = path .. ".txt"
						assert(vim.uv.fs_rename(path, name))
						vim.api.nvim_buf_set_name(buf, name)
					end
					if vim.startswith(name, scratch_root) then
						vim.api.nvim_buf_call(buf, function()
							vim.cmd("silent noautocmd write" .. (fresh and "!" or ""))
						end)
					end
				end
			end
		end)
		saving = false
		if not ok then
			error(err)
		end
	end,
})

local persisted = require("persisted")
persisted.setup({ autostart = false, autoload = false, follow_cwd = false, save_dir = session_dir })
local stdin = false
vim.api.nvim_create_autocmd("StdinReadPre", {
	callback = function()
		stdin = true
	end,
})
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		local directory = vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1
		if stdin or (vim.fn.argc() > 0 and not directory) then
			return
		end
		if directory then
			vim.api.nvim_set_current_dir(vim.fn.fnamemodify(vim.fn.argv(0), ":p"))
			scratch_dir = scratch_root .. vim.fn.sha256(vim.fn.getcwd())
		end
		vim.g.persisting_session = persisted.current()
		persisted.start()
		persisted.load({ autoload = true })
	end,
})

vim.keymap.set("n", "<leader>sn", "<cmd>enew<cr>", { desc = "New persistent scratch note" })
vim.keymap.set("n", "<leader>sf", function()
	vim.fn.mkdir(scratch_dir, "p", 448)
	require("telescope.builtin").find_files({ cwd = scratch_dir, prompt_title = "Scratch notes" })
end, { desc = "Find project scratch notes" })
