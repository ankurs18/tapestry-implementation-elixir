defmodule Tapestry.CLI do
  def run(argv) do
    argv
    |> parse_args
    |> process
  end

  defp parse_args(args) do
    parse = OptionParser.parse(args, aliases: [h: :help], switches: [help: :boolean])

    case parse do
      {[help: true], _, _} ->
        :help

      {_, [num_nodes, num_requests], _} ->
        {num_nodes, num_requests}

      {_, [num_nodes, num_requests, failure_percentage], _} ->
        {num_nodes, num_requests, failure_percentage}

      _ ->
        :help
    end
  end

  defp process(:help) do
    IO.puts("""
    Usage: mix run proj1.exs <num_nodes> <num_requests> <failure_percentage>
    Note: failure_percentage is an optional argument to check output in case of failure nodes
    """)

    System.halt(0)
  end

  defp process({num_nodes, num_requests}) do
    num_nodes = String.to_integer(num_nodes)
    num_requests = String.to_integer(num_requests)

    if(num_nodes <= num_requests) do
      IO.puts("""
        Error: Num of nodes should be greater than number of requests entered 
        Usage: mix run proj1.exs <num_nodes> <num_requests> <failure_percentage>
      """)

      System.halt(0)
    else
      Tapestry.Main.start(num_nodes, num_requests)
    end
  end

  defp process({num_nodes, num_requests, failure_percentage}) do
    num_nodes = String.to_integer(num_nodes)
    num_requests = String.to_integer(num_requests)
    failure_percentage = String.to_integer(failure_percentage)

    if(num_nodes <= num_requests) do
      IO.puts("""
        Error: Num of nodes should be greater than number of requests entered
        Usage: mix run proj1.exs <num_nodes> <num_requests> <failure_percentage>
      """)

      System.halt(0)
    else
      Tapestry.Main.start(num_nodes, num_requests, failure_percentage)
    end
  end
end
