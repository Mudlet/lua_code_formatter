--[[
  The most annouying problem is that we do not know what sort of
  handler we call: will it use variate() or not. Also normal handlers
  do not return result values. So handlers that use variate()
  return result in <printer.has_failed_to_represent>. We nullify this
  field before calling handler and check it's value after. If it is
  not nil, handler used variate() and we handle this accordingly.

  Another problem is that we should return result even it is not
  valid in terms of <multiline_allowed> and representation_is_allowed().
  This is for case when we have no other choice.
  --
  Current architecture easily becomes a performance black hole.
  Consider we are formatting a statement "a = {z = {}}". It parsed
  to something like

    <assignment>("a", <table>( ("z", <table>() ) ) )

  Both <assignment> and <table> have one-line and multiline versions.
  So we iterate from multiline to oneline as

    <assignment-m> <table-m> <table-m>
                             <table-1>
                   <table-1> <table-1>
    <assignment-1> <table-1> <table-1>

  The problem is that internal nodes called many times for same
  values, differed only by parent function who called it and usually
  by indentation in "printer" device abstraction.

  Also for a table with many values we anyway call one-line version
  which will fail in representation_is_allowed() function.
]]

local states = {}

local add =
  function(state)
    states[#states + 1] = state
  end

local get =
  function()
    return states[#states]
  end

local is_empty =
  function()
    return (#states == 0)
  end

local remove =
  function()
    states[#states] = nil
  end

local is_multiline_allowed =
  function()
    if is_empty() then
      return true
    else
      return get()
    end
  end

local split_last_line = request('^.^.^.string.split_last_line')

local get_handler =
  function(handler_rec)
    local handler, handler_is_multiline
    if is_table(handler_rec) then
      handler = handler_rec[1]
      handler_is_multiline = handler_rec.is_multiline
    elseif is_function(handler_rec) then
      handler = handler_rec
    end
    if is_nil(handler_is_multiline) then
      handler_is_multiline = false
    end
    assert_function(handler)
    assert_boolean(handler_is_multiline)
    return handler, handler_is_multiline
  end

local get_most_suitable_handler =
  function(representers, is_multiline_allowed)
    local result, is_multiline

    if not result then
      for i = 1, #representers do
        local handler, handler_is_multiline = get_handler(representers[i])
        if (handler_is_multiline and is_multiline_allowed) then
          result, is_multiline = handler, handler_is_multiline
          break
        end
      end
    end
    if not result then
      for i = 1, #representers do
        local handler, handler_is_multiline = get_handler(representers[i])
        if (not handler_is_multiline and not is_multiline_allowed) then
          result, is_multiline = handler, handler_is_multiline
          break
        end
      end
    end
    if not result then
      for i = 1, #representers do
        local handler, handler_is_multiline = get_handler(representers[i])
        if (not handler_is_multiline and is_multiline_allowed) then
          result, is_multiline = handler, handler_is_multiline
          break
        end
      end
    end
    if not result then
      for i = 1, #representers do
        local handler, handler_is_multiline = get_handler(representers[i])
        if (handler_is_multiline and not is_multiline_allowed) then
          result, is_multiline = handler, handler_is_multiline
          break
        end
      end
    end

    assert(result)
    return result, is_multiline
  end

return
  function(self, representers, node)
    local init_state = self.printer:get_state()
    local init_text = self.printer:get_text()
    local init_text_base, init_last_line = split_last_line(init_text)

    local represent =
      function(self, handler, handler_is_multiline, node)
        self.printer:set_state(init_state)
        self.printer.text:init()
        self.printer.text:add(init_last_line)

        add(handler_is_multiline)
        self.printer.has_failed_to_represent = nil
        handler(self, node)
        local has_failed
        if is_nil(self.printer.has_failed_to_represent) then
          has_failed = false
        else
          has_failed = self.printer.has_failed_to_represent
        end
        self.printer.has_failed_to_represent = nil
        remove()

        local state = self.printer:get_state()
        local text = self.printer:get_text()

        -- print(('[%s]'):format(text))
        return state, text, has_failed
      end

    local good_state, good_text
    local failsafe_state, failsafe_text
    --[[
    if self.representation_is_allowed(init_last_line) then
      for i = 1, #representers do
        local handler, handler_is_multiline = get_handler(representers[i])
        if
          is_multiline_allowed() or
          (not is_multiline_allowed() and not handler_is_multiline)
        then
          -- print('optimal_search')
          local state, text, has_failed = represent(self, handler, handler_is_multiline, node)
          if not has_failed and self.representation_is_allowed(text) then
            good_state, good_text = state, text
            -- print(('good_text: [%s]'):format(text))
          elseif not failsafe_state then
            failsafe_state, failsafe_text = state, text
          end
        end
      end
    end
    --]]

    if not good_state and not failsafe_state then
      local handler, handler_is_multiline =
        get_most_suitable_handler(representers, is_multiline_allowed())
      -- print('failsafe')
      failsafe_state, failsafe_text =
        represent(self, handler, handler_is_multiline, node)
    end

    self.printer.text:init()
    self.printer.text:add(init_text_base)
    if good_state then
      self.printer:set_state(good_state)
      self.printer.text:add(good_text)
      self.printer.has_failed_to_represent = false
    else
      self.printer:set_state(failsafe_state)
      self.printer.text:add(failsafe_text)
      self.printer.has_failed_to_represent = true
    end
  end
