local source = {}
local util = require("copilot.util")
local existing_matches = {}

local get_line = function (line)
  local line_text = vim.api.nvim_buf_get_lines(0, line, line+1, false)[1]
  return line_text
end

local get_line_text = function (name)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]-1
  return name == "current" and get_line(current_line) or get_line(current_line+1)
end

local function split_remove_trailing_newline(str)
  local list = vim.fn.split(str, "\n")
  if list[#list] == "" then
    list[#list] = nil
  end
  return list
end

local get_text_after_cursor = function()
  local current_line = vim.api.nvim_get_current_line()
  return current_line:sub(vim.api.nvim_win_get_cursor(0)[2]+1)
end

local remove_string_from_end = function(str, str_to_remove)
  if str:sub(-#str_to_remove) == str_to_remove then
    return str:sub(1, -#str_to_remove - 1)
  end
  return str
end

local clean_insertion = function(text)
  local indent = string.match(text, '^%s*')
  if not indent then return text end
  local list = split_remove_trailing_newline(string.gsub(text, '^' .. indent, ''))
  list[1] = remove_string_from_end(list[1], get_text_after_cursor())
  if #list > 1 then
    list[#list] = remove_string_from_end(list[#list], get_line_text("next"))
  end
  return remove_string_from_end(table.concat(list, '\n'), '\n')
end

local get_range = function (item, params)
  return {
    start = item.range.start,
    ['end'] = params.context.cursor,
  }
end

local format_completions = function(params, completions)
  local formatted = {
    IsIncomplete = true,
    items = vim.tbl_map(function(item)
      item = vim.tbl_extend('force', {}, item)
      local cleaned = source.deindent(item.text)
      return {
        label = cleaned,
        kind = 15,
        textEdit = source.format_and_clean_insertion(item, params),
        documentation = {
          kind = "markdown",
          value = "```" .. vim.bo.filetype .. "\n" .. cleaned .. "\n```"
        },
      }
    end, completions)
  }
  return formatted
end

source.format_and_clean_insertion = function(item, params)
  local deindented = clean_insertion(item.text)
  return {
    range = get_range(item, params),
    newText = deindented
  }
end

source.new = function(opts)
  local self = setmetatable({ timer = vim.loop.new_timer() }, { __index = source })
  self.client = opts.client
  print(opts.custom_completion_function)
  source.completion_trigger_function = opts.custom_completion_function or self.defaults.completion_trigger_function
  self.request_ids = {}
  print(vim.inspect(self))
  return self
end

source.defaults = {
  completion_trigger_function = function(params, callback)
    existing_matches[params.context.bufnr] = existing_matches[params.context.bufnr] or {}
    existing_matches[params.context.bufnr][params.context.cursor.row] = existing_matches[params.context.bufnr][params.context.cursor.row] or { IsIncomplete = true }
    local existing = existing_matches[params.context.bufnr][params.context.cursor.row]
    local has_complete = false
    vim.lsp.buf_request(0, "getCompletionsCycling", util.get_completion_params(), function(_, response)
      if response and not vim.tbl_isempty(response.completions) then
        existing = vim.tbl_deep_extend("force", existing, format_completions(params, response.completions))
        has_complete = true
      end
      vim.schedule(function() callback(existing) end)
    end)
    if not has_complete then
      callback(existing)
    end
  end,
}

source.get_trigger_characters = function()
  return { "\t", "\n", ".", ":", "(", "'", '"', "[", ",", "#", "*", "@", "|", "=", "-", "{", "/", "\\", " ", "+", "?"}
end

source.is_available = function(self)
  -- client is stopped.
  if self.client.is_stopped() then
    return false
  end
  -- client is not attached to current buffer.
  if not vim.lsp.buf_get_clients(vim.api.nvim_get_current_buf())[self.client.id] then
    return false
  end
  if not self.client.name == "copilot" then
    return false
  end
  return true
end

source.deindent = function(text)
  local indent = string.match(text, '^%s*')
  if not indent then
    return text
  end
  return string.gsub(string.gsub(text, '^' .. indent, ''), '\n' .. indent, '\n')
end

source.complete = function(self, params, callback)
  print(source.completion_trigger_function(params, callback))
end

return source
