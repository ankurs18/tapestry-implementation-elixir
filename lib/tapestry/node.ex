defmodule Tapestry.Node do
  use GenServer, restart: :transient

  def start_link(id) do
    GenServer.start_link(__MODULE__, id)
  end

  def init(id) do
    id = id
    {:ok, {id, %{}, false, 0, 0}}
  end

  ################# client end #####################

  def fetch_id(pid), do: GenServer.call(pid, {:fetch_id}, :infinity)

  def check_active(pid), do: GenServer.call(pid, {:is_active}, :infinity)

  def get_completed_requests_num(pid),
    do: GenServer.call(pid, {:completed_requests_num}, :infinity)

  def get_hop(pid), do: GenServer.call(pid, {:get_hop}, :infinity)

  def set_neighbors(pid, node_ids), do: GenServer.cast(pid, {:set_neighbors, node_ids})

  def set_neighbors_dynamic(pid, exisitng_id_pid_map),
    do: GenServer.cast(pid, {:set_neighbors_dynamic, exisitng_id_pid_map})

  def get_routing_table(pid), do: GenServer.call(pid, {:get_routing_table})

  def send_message(
        pid,
        sender_id,
        receiver_id,
        pid_id_map,
        old_id_pid_map,
        hop,
        is_failure,
        visited_set \\ MapSet.new()
      ),
      do:
        GenServer.cast(
          pid,
          {:send_message,
           {sender_id, receiver_id, pid_id_map, old_id_pid_map, hop, is_failure, visited_set}}
        )

  def update_hop(pid, hop), do: GenServer.cast(pid, {:update_hop, hop})
  defp find_index(array, val), do: Enum.find_index(array, fn x -> x == val end)

  defp get_alive_map(map, id_pid_map) do
    Enum.reduce(map, map, fn {match_level, rows}, acc ->
      alive_nodes_at_level =
        Enum.reduce(rows, %{}, fn {letter, list_nodes}, row_acc ->
          filtered_list =
            Enum.filter(list_nodes, fn x -> Process.alive?(Map.get(id_pid_map, x)) end)

          if length(filtered_list) > 0, do: Map.put(row_acc, letter, filtered_list), else: row_acc
        end)

      if map_size(alive_nodes_at_level) > 0,
        do:
          Map.put(
            acc,
            match_level,
            alive_nodes_at_level
          ),
        else: acc
    end)
  end

  defp remove_visited_node(map, node_to_remove) do
    Enum.reduce(map, %{}, fn {match_level, rows}, acc ->
      nodes_at_level =
        Enum.reduce(rows, %{}, fn {letter, list_nodes}, row_acc ->
          filtered_list = Enum.filter(list_nodes, fn x -> x != node_to_remove end)
          if length(filtered_list) > 0, do: Map.put(row_acc, letter, filtered_list), else: row_acc
        end)

      if map_size(nodes_at_level) > 0,
        do:
          Map.put(
            acc,
            match_level,
            nodes_at_level
          ),
        else: acc
    end)
  end

  def get_hop_neighbor(
        id,
        neighbors_map,
        receiver_id,
        match_level,
        closest_node_level,
        old_id_pid_map,
        visited_set,
        is_failure
      ) do
    # IO.inspect({"First", neighbors_map, match_level})
    neighbors_map =
      if(is_failure) do
        get_alive_map(neighbors_map, old_id_pid_map)
      else
        neighbors_map
      end

    level_neighbors = Map.get(neighbors_map, match_level)
    hex_array = Tapestry.Main.hexadecimal()

    if(level_neighbors == %{} or level_neighbors == nil) do
      get_hop_neighbor(
        id,
        neighbors_map,
        receiver_id,
        match_level - 1,
        closest_node_level,
        old_id_pid_map,
        visited_set,
        is_failure
      )
    else
      closest_nodes = Map.get(level_neighbors, closest_node_level)

      closestNode =
        if(closest_nodes != nil and length(closest_nodes) > 0) do
          # picking the next max
          Enum.max_by(closest_nodes, fn id -> String.jaro_distance(id, receiver_id) end)
        else
          surrogate_level =
            Enum.max_by(Map.keys(level_neighbors), fn letter ->
              -abs(find_index(hex_array, letter) - find_index(hex_array, closest_node_level))
            end)

          closest_nodes = Map.get(level_neighbors, surrogate_level)

          Enum.max_by(closest_nodes, fn id -> String.jaro_distance(id, receiver_id) end)
        end

      # checks if it is getting stuck in a loop
      closestNode =
        if(MapSet.member?(visited_set, closestNode)) do
          neighbors_map = remove_visited_node(neighbors_map, closestNode)

          get_hop_neighbor(
            id,
            neighbors_map,
            receiver_id,
            match_level,
            closest_node_level,
            old_id_pid_map,
            visited_set,
            is_failure
          )
        else
          closestNode
        end

      closestNode
    end
  end

  ################# Server end #####################
  @doc """
  Updates the maximum hop for all request in the node
  """
  def handle_cast(
        {:update_hop, maxHop},
        {id, neighbors_map, is_active, hop, completedRequest}
      ) do
    hop =
      if(hop == nil) do
        maxHop
      else
        if(maxHop > hop) do
          maxHop
        else
          hop
        end
      end

    # IO.inspect({"Hop: ", hop, "Request:", completedRequest, "id:", id})
    {:noreply, {id, neighbors_map, is_active, hop, completedRequest + 1}}
  end

  @doc """
  routes a message from the node to a receiver_id and updating the hopCount
  """
  def handle_cast(
        {:send_message,
         {sender_id, receiver_id, pid_id_map, old_id_pid_map, hopCount, is_failure, visited_set}},
        {id, neighbors_map, is_active, hop, completedRequest}
      ) do
    match_level = count_match_level(id, receiver_id)
    # IO.inspect({"From:", sender_id, "To:", receiver_id, hopCount})

    if(id == receiver_id) do
      update_hop(Map.get(pid_id_map, sender_id), hopCount)
    else
      next_node_id =
        get_hop_neighbor(
          id,
          neighbors_map,
          receiver_id,
          match_level,
          String.at(receiver_id, match_level - 1),
          old_id_pid_map,
          visited_set,
          is_failure
        )

      send_message(
        Map.get(pid_id_map, next_node_id),
        sender_id,
        receiver_id,
        pid_id_map,
        old_id_pid_map,
        hopCount + 1,
        is_failure,
        MapSet.put(visited_set, next_node_id)
      )
    end

    {:noreply, {id, neighbors_map, is_active, hop, completedRequest}}
  end

  @doc """
  creates the routing table ans setting it up in the state of the node
  """
  def handle_cast(
        {:set_neighbors, node_ids},
        {id, _neighbors_map, _is_active, hop, completedRequest}
      ) do
    neighbors_map =
      Enum.reduce(Enum.shuffle(node_ids) -- [id], Map.new(), fn curr_id, acc ->
        match_level = count_match_level(id, curr_id)
        curr_neighbors = Map.get(acc, match_level)

        curr_neighbors =
          if curr_neighbors != nil do
            curr_list = Map.get(curr_neighbors, String.at(curr_id, match_level - 1))

            curr_list =
              cond do
                curr_list == nil -> [curr_id]
                length(curr_list) < 3 -> [curr_id | curr_list]
                true -> curr_list
              end

            Map.put(curr_neighbors, String.at(curr_id, match_level - 1), curr_list)
          else
            # curr_letter = String.at(curr_id, match_level - 1)
            %{String.at(curr_id, match_level - 1) => [curr_id]}
          end

        Map.put(acc, match_level, curr_neighbors)
      end)

    # IO.inspect(neighbors_map)
    {:noreply, {id, neighbors_map, true, hop, completedRequest}}
  end

  @doc """
  adds the neighbor map in the state of dynamically inserted node
  """
  def handle_cast(
        {:set_neighbors_dynamic, exisitng_id_pid_map},
        {id, _neighbors_map, _is_active, hop, completedRequest}
      ) do
    exisiting_node_ids = Map.keys(exisitng_id_pid_map)
    {match_level, match_id} = find_best_matching_id(exisiting_node_ids, id)

    closest_routing_table =
      get_routing_table(Map.get(exisitng_id_pid_map, match_id))
      |> Enum.reduce(%{}, fn {level, neighbors}, acc ->
        if level <= match_level, do: Map.put(acc, level, neighbors), else: acc
      end)

    send_neighbors_update(id, closest_routing_table, exisitng_id_pid_map)
    GenServer.cast(Map.get(exisitng_id_pid_map, match_id), {:update_neighbors, id})

    closest_routing_table =
      fill_higher_routing_table(id, closest_routing_table, match_level, exisiting_node_ids)

    {:noreply, {id, closest_routing_table, true, hop, completedRequest}}
  end

  @doc """
  receives the new dynamically inserted node id to update the routing table
  """
  def handle_cast(
        {:update_neighbors, new_node_id},
        {id, neighbors_map, _is_active, hop, completedRequest}
      ) do
    curr_match_level = count_match_level(new_node_id, id)
    curr_row = Map.get(neighbors_map, curr_match_level)

    curr_row =
      if curr_row != nil do
        curr_cell = Map.get(curr_row, String.at(new_node_id, curr_match_level - 1))

        curr_cell =
          cond do
            curr_cell == nil -> [new_node_id]
            length(curr_cell) < 3 -> [new_node_id | curr_cell]
            true -> curr_cell
          end

        Map.put(curr_row, String.at(new_node_id, curr_match_level - 1), curr_cell)
      else
        %{String.at(new_node_id, curr_match_level - 1) => [new_node_id]}
      end

    new_neighbors_map = Map.put(neighbors_map, curr_match_level, curr_row)

    # IO.inspect(new_neighbors_map)
    {:noreply, {id, new_neighbors_map, true, hop, completedRequest}}
  end

  @doc """
  to get the current node's id
  """
  def handle_call({:fetch_id}, _from, {id, neighbors_map, is_active, hop, completedRequest}) do
    {:reply, id, {id, neighbors_map, is_active, hop, completedRequest}}
  end

  @doc """
  to get the current node's is_active after the routing table is created
  """
  def handle_call({:is_active}, _from, {id, neighbors_map, is_active, hop, completedRequest}) do
    {:reply, is_active, {id, neighbors_map, is_active, hop, completedRequest}}
  end

  @doc """
  to get the current node's maximum hop count
  """
  def handle_call({:get_hop}, _from, {id, neighbors_map, is_active, hop, completedRequest}) do
    {:reply, hop, {id, neighbors_map, is_active, hop, completedRequest}}
  end

  @doc """
  to get the current node's number of requests got completed
  """
  def handle_call(
        {:completed_requests_num},
        _from,
        {id, neighbors_map, is_active, hop, completedRequest}
      ) do
    {:reply, completedRequest, {id, neighbors_map, is_active, hop, completedRequest}}
  end

  @doc """
  to get the current node's routing table
  """
  def handle_call(
        {:get_routing_table},
        _from,
        {id, neighbors_map, is_active, hop, completedRequest}
      ) do
    {:reply, neighbors_map, {id, neighbors_map, is_active, hop, completedRequest}}
  end

  @doc """
  helper function matching prefixes two node ids
  """
  def count_match_level(string1 \\ "ankur", string2 \\ "rahul") do
    count_match_level(string1, string2, 0)
  end

  defp count_match_level(string1, string2, i) do
    cond do
      i == 8 -> 8
      String.at(string1, i) == String.at(string2, i) -> count_match_level(string1, string2, i + 1)
      true -> i + 1
    end
  end

  # helper function to find maximum matching node
  defp find_best_matching_id(exisiting_node_ids, self_id) do
    Enum.reduce(exisiting_node_ids, {0, ""}, fn node_id, {max, id} ->
      curr_match_level = count_match_level(node_id, self_id)
      if curr_match_level > max, do: {curr_match_level, node_id}, else: {max, id}
    end)
  end

  # helper function to fill routing tables above maximum matched prefix levels(P)
  defp fill_higher_routing_table(id, closest_routing_table, match_level, node_ids) do
    neighbors_map =
      Enum.reduce(Enum.shuffle(node_ids) -- [id], closest_routing_table, fn curr_id, acc ->
        curr_match_level = count_match_level(id, curr_id)

        if curr_match_level == 1 or curr_match_level > match_level do
          curr_neighbors = Map.get(acc, curr_match_level)

          curr_neighbors =
            if curr_neighbors != nil do
              curr_list = Map.get(curr_neighbors, String.at(curr_id, match_level - 1))

              curr_list =
                cond do
                  curr_list == nil -> [curr_id]
                  length(curr_list) < 3 -> [curr_id | curr_list]
                  true -> curr_list
                end

              Map.put(curr_neighbors, String.at(curr_id, curr_match_level - 1), curr_list)
            else
              # curr_letter = String.at(curr_id, match_level - 1)
              %{String.at(curr_id, curr_match_level - 1) => [curr_id]}
            end

          Map.put(acc, curr_match_level, curr_neighbors)
        else
          acc
        end
      end)

    # IO.puts("#{id} ->")
    neighbors_map
  end

  # helper function to mulicast to other nodes regarding the new dynamically added node.
  defp send_neighbors_update(self_id, routing_table, id_pid_map) do
    Enum.each(routing_table, fn {_level, columns} ->
      Enum.each(columns, fn {_columns, node_ids} ->
        Enum.each(node_ids, fn node_id ->
          pid = Map.get(id_pid_map, node_id)
          GenServer.cast(pid, {:update_neighbors, self_id})
        end)
      end)
    end)
  end
end
