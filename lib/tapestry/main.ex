defmodule Tapestry.Main do
  @hexadecimal ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
  def hexadecimal, do: @hexadecimal

  def start(num_nodes \\ 10, num_requests \\ 5, failure_percentage \\ 0) do
    start_time = System.monotonic_time(:millisecond)
    node_ids = generate_nodenums(num_nodes - 1)
    id_pid_map = start_nodes(node_ids)
    pids = Map.values(id_pid_map)
    set_neighbors(pids, node_ids)
    # Infinite Loop
    check_active_ids(pids, num_nodes - 1)
    # IO.puts("Nodes generated with routing tables")

    {_new_node_ids, new_id_pid_map} = add_new_nodes(id_pid_map)

    id_pid_map = Map.merge(id_pid_map, new_id_pid_map)
    pids = pids ++ Map.values(new_id_pid_map)

    # IO.puts("Time taken in Node Generation: #{System.monotonic_time(:millisecond) - start_time}")

    new_id_pid_map =
      if failure_percentage > 0, do: kill_nodes(id_pid_map, failure_percentage), else: id_pid_map

    pids = if failure_percentage > 0, do: Map.values(new_id_pid_map), else: pids

    send_messages(
      Map.keys(new_id_pid_map),
      new_id_pid_map,
      id_pid_map,
      num_requests,
      failure_percentage > 0
    )

    # check_request_completed(pids, num_nodes, num_requests)
    num_nodes = num_nodes - ((failure_percentage / 100 * num_nodes) |> round())
    # IO.inspect({"Number of nodes:", num_nodes})
    check_request_completed(pids, num_nodes, num_requests)

    maxHop =
      Enum.reduce(pids, 0, fn pid, max ->
        current_hop = Tapestry.Node.get_hop(pid)

        max =
          if current_hop > max,
            do: current_hop,
            else: max

        max
      end)

    IO.puts("Maximum Hop: #{maxHop}")
    IO.puts("Total time taken: #{System.monotonic_time(:millisecond) - start_time}")
  end

  def send_messages(node_ids, new_id_pid_map, id_pid_map, num_requests, is_failure) do
    Enum.each(node_ids, fn node_id ->
      Task.start_link(__MODULE__, :send_message_after_interval, [
        node_id,
        node_ids -- [node_id],
        new_id_pid_map,
        id_pid_map,
        num_requests,
        is_failure
      ])
    end)
  end

  def send_message_after_interval(
        node_id,
        other_node_ids,
        new_id_pid_map,
        id_pid_map,
        num_requests,
        is_failure
      ) do
    if(num_requests > 0 and length(other_node_ids) > 0) do
      target_node_id = Enum.random(other_node_ids)

      Tapestry.Node.send_message(
        Map.get(new_id_pid_map, node_id),
        node_id,
        target_node_id,
        new_id_pid_map,
        id_pid_map,
        0,
        is_failure
      )

      Process.sleep(1000)

      send_message_after_interval(
        node_id,
        other_node_ids -- [target_node_id],
        new_id_pid_map,
        id_pid_map,
        num_requests - 1,
        is_failure
      )
    end
  end

  defp kill_nodes(id_pid_map, failure_percent) do
    num_failure_nodes = (failure_percent / 100 * map_size(id_pid_map)) |> round()
    IO.puts("nodes to kill: #{num_failure_nodes}")

    killed_nodes = kill_unique(id_pid_map, num_failure_nodes)

    map =
      Enum.reduce(killed_nodes, id_pid_map, fn {id, _pid}, acc ->
        Map.delete(acc, id)
      end)

    map
  end

  defp kill_unique(id_pid_map, num_nodes_tokill, killed_nodes \\ %{}) do
    if(num_nodes_tokill == 0) do
      killed_nodes
    else
      {unlucky_id, unlucky_pid} = Enum.random(id_pid_map)

      if Map.has_key?(killed_nodes, unlucky_id) do
        kill_unique(id_pid_map, num_nodes_tokill, killed_nodes)
      else
        Process.exit(unlucky_pid, :shutdown)

        kill_unique(
          id_pid_map,
          num_nodes_tokill - 1,
          Map.put(killed_nodes, unlucky_id, unlucky_pid)
        )
      end
    end
  end

  defp add_new_nodes(exisitng_id_pid_map, num_new_nodes \\ 1) do
    exisitng_node_ids = Map.keys(exisitng_id_pid_map) |> MapSet.new()

    new_node_ids =
      Enum.reduce(1..num_new_nodes, MapSet.new(), fn _, acc ->
        new_id = generate_unique(MapSet.union(exisitng_node_ids, acc))
        MapSet.put(acc, new_id)
      end)

    new_id_pid_map =
      Enum.reduce(new_node_ids, Map.new(), fn node_id, acc ->
        pid = Tapestry.NodeSupervisor.start_worker(node_id)
        Map.put(acc, node_id, pid)
      end)

    add_neighbors_dynamically(exisitng_id_pid_map, new_id_pid_map)

    {new_node_ids, new_id_pid_map}
  end

  defp add_neighbors_dynamically(exisitng_id_pid_map, new_id_pid_map) do
    Enum.each(Map.values(new_id_pid_map), fn pid ->
      Tapestry.Node.set_neighbors_dynamic(pid, exisitng_id_pid_map)
    end)
  end

  defp generate_nodenums(num_nodes) do
    Enum.reduce(1..num_nodes, MapSet.new(), &add_unique/2)
  end

  defp start_nodes(node_ids) do
    Enum.reduce(node_ids, Map.new(), fn node_id, acc ->
      pid = Tapestry.NodeSupervisor.start_worker(node_id)
      Map.put(acc, node_id, pid)
    end)
  end

  defp check_active_ids(pids, num_nodes) do
    active_pids =
      Enum.reduce(pids, 0, fn pid, count ->
        if Tapestry.Node.check_active(pid) == true, do: count + 1, else: count
      end)

    if active_pids < num_nodes, do: check_active_ids(pids, num_nodes), else: :ok
  end

  defp check_request_completed(pids, num_nodes, num_requests) do
    completed_pids_count =
      Enum.reduce(pids, 0, fn pid, count ->
        if Tapestry.Node.get_completed_requests_num(pid) == num_requests,
          do: count + 1,
          else: count
      end)

    # IO.inspect({"completed: ", completed_pids_count})

    if completed_pids_count < num_nodes,
      do: check_request_completed(pids, num_nodes, num_requests),
      else: :ok
  end

  defp generate_unique(exisitng_node_ids) do
    new_id = Enum.join(Enum.reduce(1..8, [], fn _, acc -> [Enum.random(@hexadecimal) | acc] end))

    if !MapSet.member?(exisitng_node_ids, new_id),
      do: new_id,
      else: generate_unique(exisitng_node_ids)
  end

  defp add_unique(_, acc) do
    new_set =
      MapSet.put(
        acc,
        Enum.join(Enum.reduce(1..8, [], fn _, gen -> [Enum.random(@hexadecimal) | gen] end))
      )

    if MapSet.size(acc) < MapSet.size(new_set), do: new_set, else: add_unique(1, acc)
  end

  defp set_neighbors(pids, node_ids) do
    Enum.each(pids, fn pid ->
      Tapestry.Node.set_neighbors(pid, node_ids)
    end)
  end
end
