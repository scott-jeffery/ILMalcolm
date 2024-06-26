def concurrency
  :shared
end

def register(params)
  _discard_zeroes_str = params["discard_zeroes"]
  @discard_zeroes = [1, true, '1', 'true', 't', 'on', 'enabled'].include?(_discard_zeroes_str.to_s.downcase)
end

def compact(h)
  h.inject({}) do |result, (k, v)|
    case v
    when Hash
      c = compact(v)
      result[k] = c unless c.empty?
    when String
      result[k] = v unless (v.empty? || (v == "-") || (v == "?") || (v == "(empty)") || (v == "(none)") || (v == "(null)") || (v == "NULL") || (v == "unset") || (v == "Nul") || (@discard_zeroes && ((v == "0") || (v == "0x0"))))
    when Numeric
      result[k] = v unless (@discard_zeroes && v.zero?)
    when Array
      c = v.delete_if{|e| e.nil? || (e.is_a?(String) && (e.empty? || (e == "-") || (e == "?") || (e == "(empty)") || (e == "(none)") || (e == "(null)") || (e == "NULL") || (e == "unset") || (e == "Nul") || (@discard_zeroes && ((e == "0") || (e == "0x0")))))}
      result[k] = c unless c.empty?
    when NilClass
      # nothing
    else
      result[k] = v
    end
    result
  end
end

def filter(event)
  return [LogStash::Event.new(compact(event.to_hash_with_metadata))]
end

###############################################################################
# tests

test "remove keys with nil values" do

  in_event { { "foo" => 1, "bar" => nil, "blat" => "-", "blarg" => "(empty)", "nested" => { "baz" => nil, "biz" => "yo" }} }

  expect("return a single event") do |events|
    events.size == 1
  end

  expect("kept the foo key") do |events|
    events.first.get("[foo]") == 1
  end

  expect("kept the [nested][biz] key") do |events|
    events.first.get("[nested][biz]") == "yo"
  end

  expect("remove the bar key") do |events|
    !events.first.include?("[bar]")
  end

  expect("remove the baz key") do |events|
    !events.first.include?("[nested][baz]")
  end

  expect("remove the blat key") do |events|
    !events.first.include?("[blat]")
  end

  expect("remove the blarg key") do |events|
    !events.first.include?("[blarg]")
  end
end
