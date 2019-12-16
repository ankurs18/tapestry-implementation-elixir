defmodule Tapestry do
  @moduledoc """
  Documentation for Tapestry.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Tapestry.hello()
      :world

  """
  def main(args \\ []) do
    [numNodes, numRequests, failure] = args

    numNodes = getParsesInteger(numNodes)

    numRequests = getParsesInteger(numRequests)

    numRequests =
      if(numNodes == numRequests) do
        numRequests - 1
      else
        numRequests
      end

    failure = getParsesInteger(failure)

    Tapestry.Main.start(numNodes, numRequests, failure)
  end

  def getParsesInteger(val) do
    if(String.valid?(val)) do
      elem(Integer.parse(val), 0)
    else
      val
    end
  end
end
