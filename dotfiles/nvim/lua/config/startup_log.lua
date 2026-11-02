-- Writes every warning/error raised during startup to a log file, so they can
-- be read after the fact instead of scrolling past in the UI.
--
-- Log file: stdpath("log")/startup-errors.log
--   Windows: %LOCALAPPDATA%\nvim-data\startup-errors.log
--   Linux:   ~/.local/state/nvim/startup-errors.log
--
-- Two capture paths, because plugins report problems in two different ways:
--   1. vim.notify (lazy.nvim, LazyVim, most plugins) is wrapped from the very
--      first line of startup. Later, snacks.nvim replaces vim.notify, so once
--      it is loaded its notification history is dumped as well.
--   2. Plain error messages (the ones :messages shows) are dumped on VimEnter.

local path = vim.fs.joinpath(vim.fn.stdpath("log"), "startup-errors.log")
local WARN = vim.log.levels.WARN

local function write(lines, append)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path, append and "a" or "")
end

local function block(title, text)
  local out = { "", "---- " .. title .. " ----" }
  vim.list_extend(out, vim.split(text, "\n", { plain = true }))
  return out
end

-- Fresh file for every start.
write({ "== nvim startup " .. os.date("%Y-%m-%d %H:%M:%S") .. " ==" })

-- 1) Catch notifications emitted before any plugin replaces vim.notify.
local original_notify = vim.notify
vim.notify = function(msg, level, opts)
  if (level or vim.log.levels.INFO) >= WARN then
    local title = opts and opts.title or "notify"
    write(block("notify: " .. title, type(msg) == "string" and msg or vim.inspect(msg)), true)
  end
  return original_notify(msg, level, opts)
end

-- 2) After startup settles, dump :messages and the snacks notification history.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      local lines = {}

      local messages = vim.fn.execute("messages")
      if messages:match("%S") then
        vim.list_extend(lines, block(":messages", messages))
      end

      local ok, snacks = pcall(require, "snacks")
      if ok and snacks.notifier then
        for _, n in ipairs(snacks.notifier.get_history({ level = { "warn", "error" } })) do
          local title = ("snacks %s: %s"):format(n.level, n.title or "")
          vim.list_extend(lines, block(title, type(n.msg) == "string" and n.msg or vim.inspect(n.msg)))
        end
      end

      if #lines > 0 then
        write(lines, true)
      end
    end, 2000)
  end,
})
