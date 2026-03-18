defmodule MurrayTest do
  use ExUnit.Case
  doctest Murray

  test "greets the world" do
    assert Murray.hello() == :world
  end
end
