@version 1

# Battlechain : Decentralized turn based battle game 

# max players number : 1000


# reset action points daily at midnight
# action points can be used for : attack , heal , feed and many more coming ...
# the reset is read and consumed when player do their first resfresh action of the day ( new day find)
actions triggered_by: interval, at: "0 0 * * *" do
  
  current_day = State.get("day",1)
  State.set("day", current_day + 1 )

end

# end turn every 30 minutes 
# player can do only one action per turn
actions triggered_by: interval, at: "*/30 * * * *" do
  
  current_turn = State.get("turn",1)
  State.set("turn", current_turn + 1 )

end



# player can resurrect their archmon every 12 hours
actions triggered_by: interval, at: "0 */12 * * *" do
  
  current_round = State.get("round",1)
  State.set("round", current_round + 1)

end


condition triggered_by: transaction, on: add_player(), as: [
  content:  ( 
      player_previous_address = Chain.get_previous_address(transaction)

      player = get_player(Chain.get_genesis_address(player_previous_address))
      player == nil
   )
]

actions triggered_by: transaction, on: add_player() do
  
  player_genesis_address = Chain.get_genesis_address(transaction.address)
  base_health = 10
  base_power = 2

  archmon = [ 
    level: 1,
    xp: 0,
    base_health: base_health,
    base_power: base_power,
    health: base_health,
    power: base_power,
    is_ko: false
  ]


  player = [
    action_points: 10,
    consumed_day: State.get("day",1) - 1,
    consumed_round: State.get("round",1) - 1,
    consumed_turn: State.get("turn",1) - 1 ,
    last_action: [version: 0],
    archmon: archmon
  ]

  players = State.get("players", Map.new())
  players = Map.set(players,player_genesis_address, player)
  
  State.set("players",players)

end

 

condition triggered_by: transaction, on: attack(player_address), as: [
  content:  (
            player_attacker_previous_address = Chain.get_previous_address(transaction)
            player_attacker_genesis_address = Chain.get_genesis_address(player_attacker_previous_address)
            player_defender_genesis_address = Chain.get_genesis_address(String.to_hex(player_address))
            

            player_attacker = get_player(player_attacker_genesis_address)
            player_defender = get_player(player_defender_genesis_address)
            if player_attacker_genesis_address != player_defender_genesis_address  do
            
              players_are_known? = player_attacker != nil && player_defender != nil
              archmons_ko? = !player_attacker.archmon.is_ko && !player_defender.archmon.is_ko

              players_are_known? && archmons_ko? && player_attacker.action_points > 0 && player.consumed_turn < State.get("turn",1)
           
            else 

              false 

            end

           
  )
]

actions triggered_by: transaction, on: attack(player_address) do

players = State.get("players")

 
  player_attacker_previous_address = Chain.get_previous_address(transaction)
  player_attacker_genesis_address = Chain.get_genesis_address(player_attacker_previous_address)

  player_defender_genesis_address = Chain.get_genesis_address(String.to_hex(player_address))
  

   player_attacker = Map.get(players,player_attacker_genesis_address)
   player_defender = Map.get(players,player_defender_genesis_address)

   attacker_power = player_attacker.archmon.power
   defender_health = player_defender.archmon.health - attacker_power


action_code = nil

defender_archmon =  player_defender.archmon

if defender_health <= 0  do

defender_archmon = Map.set(defender_archmon,"health", 0)
defender_archmon = Map.set(defender_archmon,"is_ko", true)


action_code = "ko"

else

defender_archmon = Map.set(defender_archmon,"health", defender_health)

action_code = "hit"


end

action = create_action(player_attacker, action_code, player_defender_genesis_address, nil)

player_defender = Map.set(player_defender,"archmon",defender_archmon )


player_attacker = Map.set(player_attacker,"last_action",action)
player_attacker = Map.set(player_attacker,"action_points", player_attacker.action_points - 1)
player_attacker = Map.set(player_attacker,"consumed_turn", State.get("turn",1))

players = Map.set(players,player_attacker_genesis_address, player_attacker)
players = Map.set(players,player_defender_genesis_address, player_defender)

State.set("players", players)

Contract.set_content(Json.to_string(action))

end


condition triggered_by: transaction, on: feed(), as: [

 content: ( 
   player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)
  player = get_player(player_genesis_address)
  player != nil && !player.archmon.is_ko && player.action_points > 0 && player.consumed_turn < State.get("turn",1)

  )

]

actions triggered_by: transaction, on: feed() do
  players = State.get("players")
  player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)
  player = Map.get(players,player_genesis_address)
  
  archmon = player.archmon

  exp_from_feed = 20
 
  xp_after_feed = archmon.xp + exp_from_feed
  xp_to_next_level = get_xp_to_next_level(archmon.level)

  message = nil

  if xp_after_feed >= xp_to_next_level do

  add_xp = xp_after_feed - xp_to_next_level
  #level up
  archmon = level_up(archmon, add_xp )

  message ="level up"

  else

  archmon = Map.set(archmon,"xp", xp_after_feed)

  message ="xp up"
  
  end

action = create_action(player, "feed",player_genesis_address,message)


player = Map.set(player,"last_action", action)
player = Map.set(player,"action_points", player.action_points - 1)
player = Map.set(player,"consumed_turn", State.get("turn",1))


player = Map.set(player,"archmon", archmon)

players = Map.set(players,player_genesis_address,player)

State.set("players", players)
Contract.set_content(Json.to_string(action))

end

condition triggered_by: transaction, on: heal(), as: [
  content: (
    player_previous_address = Chain.get_previous_address(transaction)
      player_genesis_address = Chain.get_genesis_address(player_previous_address)
      player = get_player(player_genesis_address)
      if player != nil  && player.action_points > 0 do

        player.consumed_turn < State.get("turn",1) && !player.archmon.is_ko  && player.archmon.health < player.archmon.base_health  
       
  
      else 

        false

      end
      )
]
actions triggered_by: transaction, on: heal() do
players = State.get("players")
player_previous_address = Chain.get_previous_address(transaction)
player_genesis_address = Chain.get_genesis_address(player_previous_address)

player = Map.get(players,player_genesis_address)

archmon = player.archmon

if archmon.health + archmon.power < archmon.base_health do

archmon = Map.set(archmon,"health", archmon.health + archmon.power)

else

archmon = Map.set(archmon,"health", archmon.base_health)

end


action = create_action(player, "heal", player_genesis_address, nil)



player = Map.set(player,"last_action",action)
player = Map.set(player,"action_points", player.action_points - 1 )
player = Map.set(player,"consumed_turn",State.get("turn",1))

player = Map.set(player,"archmon",archmon)

players = Map.set(players,player_genesis_address,player)

State.set("players", players)

Contract.set_content(Json.to_string(action))
  
end

condition triggered_by: transaction, on: refresh_action_points(), as: [
  content: (
    player_previous_address = Chain.get_previous_address(transaction)
    player_genesis_address = Chain.get_genesis_address(player_previous_address)
    player = get_player(player_genesis_address)
    player != nil && player.consumed_day < State.get("day", 1)) && player.action_points == 0

]

actions triggered_by: transaction, on: refresh_action_points() do
  players = State.get("players")
  player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)
  player = Map.get(players,player_genesis_address)

 player = Map.set(player,"action_points", 10)
 player = Map.set(player,"consumed_day",State.get("day",1))

players = Map.set(players,player_genesis_address, player)

State.set("players", players)
end



condition triggered_by: transaction, on: resurrect(), as: [
  content:  (
      player_previous_address = Chain.get_previous_address(transaction)
      player_genesis_address = Chain.get_genesis_address(player_previous_address)
      player = get_player(player_genesis_address)
      player != nil && player.archmon.is_ko && player.consumed_round < State.get("round",1)
       
   )

]



actions triggered_by: transaction, on: resurrect() do
  players = State.get("players")
  player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)
  player = Map.get(players,player_genesis_address )

  archmon = player.archmon
  
  archmon = Map.set(archmon, "health", archmon.base_health)
  archmon = Map.set(archmon, "is_ko", false)

  player = Map.set(player,"archmon", archmon)
  player = Map.set(player,"consumed_round", State.get("round",1))
  
  players = Map.set(players,player_genesis_address,player)
  State.set("players",players)

end

fun create_action(player,code,target,message) do

last_action = Map.get(player,"last_action")

action = [
  code: code,
  message: message,
  version: last_action.version + 1
]

action

end

fun save_action(player,action) do

  player = Map.set(player,"last_action",action)
  player = Map.set(player,"action_points", player.action_points - 1)


  player

end

fun level_up(archmon,add_xp) do

 archmon = Map.set(archmon,"base_health", archmon.base_health + 5)
 archmon = Map.set(archmon,"health", archmon.base_health)

 archmon = Map.set(archmon,"base_power", archmon.base_power + 1)
 archmon = Map.set(archmon,"power", archmon.base_power)

 archmon = Map.set(archmon,"level", archmon.level + 1)
 archmon = Map.set(archmon,"xp",add_xp)

 archmon

end

fun get_xp_to_next_level(current_level) do

 
  current_level * 20

end



fun is_known(player_genesis_address) do 
players = State.get("players", Map.new())

 player = Map.get(players, player_genesis_address)

 player != nil

end

fun get_player(player_genesis_address) do

players = State.get("players", Map.new())

 Map.get(players, player_genesis_address, nil)

end




export fun get_player_info(player_genesis_address) do
  player_genesis_address = String.to_hex(player_genesis_address)

  players = State.get("players", Map.new())


  Map.get(players, player_genesis_address, nil)


end



export fun get_archmon_info(player_genesis_address) do

player_genesis_address = String.to_hex(player_genesis_address)

players = State.get("players")

player = Map.get(players, player_genesis_address)

archmon = nil

if player do

  archmon = player.archmon

  end


  archmon

end



export fun get_last_action(player_genesis_address) do

player_genesis_address = String.to_hex(player_genesis_address)

players = State.get("players")

player = Map.get(players, player_genesis_address)

last_action = nil

if player do 

last_action = player.last_action

end

  
last_action

end

export fun get_turn() do
State.get("turn",1)

end

export fun get_round() do
State.get("round",1)

end

export fun get_day() do
State.get("day",1)

end