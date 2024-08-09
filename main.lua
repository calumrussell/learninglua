local inspect = require 'inspect'

Order = {}
OrderType = { MARKET_BUY = "0", MARKET_SELL = "1", LIMIT_BUY = "2", LIMIT_SELL = "3" }

function Order:new_market(name, qty, order_type)
  local inner = {}
  inner.name = name
  inner.qty = qty
  inner.order_type = order_type
  inner.price = nil
  inner.executed = false
  inner.execution_price = nil
  return inner
end

function Order:new_limit(name, qty, order_type, limit)
  local inner = {}
  inner.name = name
  inner.qty = qty
  inner.order_type = order_type
  inner.price = limit
  inner.executed = false
  inner.execution_price = nil
  return inner
end

OrderBook = { }

function OrderBook:new()
  local inner = {}
  setmetatable(inner, self)
  self.__index = self
  self.orders = {}
  return inner
end

function OrderBook:insert(order)
  self.orders[#self.orders+1] = order
end

Quote = {}

function Quote:new(name, bid, offer, date)
  local inner = {}
  inner.name = name
  inner.bid = bid
  inner.offer = offer
  inner.date = date
  return inner
end

function GenerateRandomQuotes(names, length)
  local full_quotes = {}
  for i = 1, length, 1 do
    local date_quotes = {}
    for _, name in ipairs(names) do
      local bid = math.random(90, 110)
      local offer = bid + 1
      date_quotes[name] = Quote:new(name, bid, offer, i)
    end
    full_quotes[i] = date_quotes
  end
  return full_quotes
end

function CheckBuy(order, quote)
  if quote.name == order.name then
    if order.order_type == OrderType.MARKET_BUY then
      order.executed = true
      order.executed_price = quote.offer
      return true
    elseif order.order_type == OrderType.LIMIT_BUY then
      if order.price > quote.offer then
        order.executed = true
        order.executed_price = quote.offer
        return true
      end
    end
  end
  return false
end

function CheckSell(order, quote)
  if quote.name == order.name then
    if order.order_type == OrderType.MARKET_SELL then
      order.executed = true
      order.executed_price = quote.bid
      return true
    elseif order.order_type == OrderType.LIMIT_SELL then
      if order.price < quote.bid then
        order.executed = true
        order.executed_price = quote.bid
        return true
      end
    end
  end
  return false
end

function ExecuteOrders(date, orderbook, quotes)
  local executed_orders = {}
  local orderbook_state = {}

  local date_quotes = quotes[date]
  for _, order in ipairs(orderbook.orders) do
    for _, quote in pairs(date_quotes) do
      if order.name ~= quote.name then
        goto continue
      end

      local buy_result = CheckBuy(order, quote)
      local sell_result = CheckSell(order, quote)

      if buy_result == false and sell_result == false then
        orderbook_state[#orderbook_state+1] = order
      elseif buy_result == true or sell_result == true then
        executed_orders[#executed_orders+1] = order
      end
        ::continue::
    end
  end

  local return_values = {}
  return_values.executed_orders = executed_orders
  return_values.orderbook_diff = orderbook_state
  return return_values
end

Position = {}

function Position:new(qty)
  local inner = {}
  inner.qty = qty
  return inner
end

MovingAverageStrategy = {}

function MovingAverageStrategy:new()
  local inner = {}
  setmetatable(inner, self)
  self.__index = self
  self.cash = 10000
  self.window_length = 5
  self.holdings = {}
  self.quote_buffer = {}
  return inner
end

function MovingAverageStrategy:update(order)
  if order.order_type == OrderType.MARKET_BUY or order.order_type == OrderType.LIMIT_BUY then
    if self.holdings ~= order.name then
      self.holdings[order.name] = 0
    end

    local order_value = order.executed_price * order.qty
    self.cash = self.cash - order_value

    local current_holdings = self.holdings[order.name]
    local new_holdings = current_holdings + order.qty


    self.holdings[order.name] = new_holdings
  else
    local current_holdings = self.holdings[order.name]
    if order.qty > current_holdings then
      error("Invalid sell order")
    end

    local order_value = order.executed_price * order.qty
    self.cash = self.cash + order_value

    local new_holdings = current_holdings - order.qty
    self.holdings[order.name] = new_holdings
  end
end

function MovingAverageStrategy:tick(quotes)
  local portfolio_value = self.cash;
  local position_values = {}

  -- Update values
  for _, quote in pairs(quotes) do
    if self.holdings[quote.name] == nil then
      position_values[quote.name] = 0
    else
      local position = self.holdings[quote.name]
      local position_value = 0
      if position == nil then
        position_value = quote.bid * position
      end

      position_values[quote.name] = position_value
      portfolio_value = portfolio_value + position_value
    end
  end

  -- Update quote_buffer
  for _, quote in pairs(quotes) do
    if self.quote_buffer[quote.name] == nil then
      self.quote_buffer[quote.name] = {}
    end

    local curr_buffer = self.quote_buffer[quote.name]
    if #curr_buffer < self.window_length then
      curr_buffer[#curr_buffer+1] = quote.offer
    else
      table.remove(curr_buffer, 1)
      curr_buffer[#curr_buffer+1] = quote.offer
    end
    self.quote_buffer[quote.name] = curr_buffer
  end

  local averages = {}
  -- Calculate averages
  for key, buffer in pairs(self.quote_buffer) do
    local sum = 0
    for _, val in ipairs(buffer) do
      sum = sum + val
    end
    averages[key] = sum / #buffer
  end


  -- Find portfolio target weight
  local orders = {}
  for _, quote in pairs(quotes) do
    local price = quote.offer
    local average = averages[quote.name]

    local signal = ((price/average) - 1) * 100

    local diff = 0
    -- Buy signal
    if signal > 5 then
      local target_value = portfolio_value * 0.48
      local target_qty = target_value / quote.offer
      local curr_qty = position_values[quote.name]
      diff = math.floor(target_qty - curr_qty)
    end

    -- Sell signal
    if signal < -5 then
      local curr_qty =  position_values[quote.name]
      if curr_qty > 0 then
        diff = -curr_qty
      end
    end

    if diff > 0 then
      local order = Order:new_market(quote.name, diff, OrderType.MARKET_BUY)
      orders[#orders+1] = order
    elseif diff < 0 then
      local order = Order:new_market(quote.name, diff, OrderType.MARKET_SELL)
      orders[#orders+1] = order
    end
  end

  return orders
end

Names = {"ABC", "BCD"}
Length = 100
local quotes = GenerateRandomQuotes(Names, Length)
local strategy = MovingAverageStrategy:new()
local orderbook = OrderBook:new()

for i = 1, Length, 1 do
  local result = ExecuteOrders(i, orderbook, quotes)
  if result.executed_orders ~= nil then
    print(inspect(result.executed_orders))
    for _, order in ipairs(result.executed_orders) do
      strategy:update(order)
    end
  end
  orderbook.orders = result.orderbook_diff

  local date_quotes = quotes[i]
  local orders = strategy:tick(date_quotes)

  for _, order in ipairs(orders) do
    orderbook:insert(order)
  end


end

