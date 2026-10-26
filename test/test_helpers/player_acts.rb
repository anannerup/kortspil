# A player's action at the bord as the client sends it (TableChannel): the
# action's name and its data, decoded by the bord's game into an engine
# intent (Table#client_intent) and carried out by the bord's one way in for
# a player's action (Table#act).
module PlayerActs
  def player_acts(table, action, player:, surroundings: Table::Surroundings.new, **data)
    table.act(player:, intent: table.client_intent(action.to_s, data.stringify_keys), surroundings:)
  end
end
