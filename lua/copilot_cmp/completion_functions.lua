local format = require("copilot_cmp.format")
local util = require("copilot.util")
local api = require("copilot.api")

local methods = {
  opts = {
    fix_pairs = true,
  }
}

methods.getCompletionsCycling = function (self, params, callback)
  local respond_callback = function(err, response)

    if err or not response or not response.completions then
      return callback({isIncomplete = false, items = {}})
    end

    local items = vim.tbl_map(function(item)
      return format.format_item(item, params.context, methods.opts, false)
    end, vim.tbl_values(response.completions))

    local items2 = vim.tbl_map(function(item)
      return format.format_item(item, params.context, methods.opts, true)
    end, vim.tbl_values(response.completions))

    local items3 = {}

    for i = 1, #items, 1 do
      items3[#items3 + 1] = items2[i]
      if items2[i].textEdit.newText ~= items[i].textEdit.newText then
        items3[#items3 + 1] = items[i]
      end
    end

    return callback({
      isIncomplete = false,
      items = items3
    })
  end

  api.get_completions_cycling(self.client, util.get_doc_params(), respond_callback)
  return callback({isIncomplete = true, items = {}})
end

methods.init = function (completion_method, opts)
  methods.opts.fix_pairs = opts.fix_pairs
  return methods[completion_method]
end

return methods
