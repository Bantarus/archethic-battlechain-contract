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





# player can resurrect their archmon every 12 hours
actions triggered_by: interval, at: "0 */12 * * *" do
  
  current_round = State.get("round",1)
  State.set("round", current_round + 1)

end

condition triggered_by: transaction, on: change_mode(mode), as: [

  content: (
    previous_address = Chain.get_previous_address(transaction)
    genesis_address = Chain.get_genesis_address(previous_address)
    genesis_address == String.to_hex("00007ff81d78413058b8c9e2799e59f2be28e3f454767d3dbe479403b40c4dff5fe9")
  )

]

actions triggered_by: transaction, on: change_mode(mode) do

State.set("mode",mode)
  
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
  base_defense = 2

  archmon = [ 
    level: 1,
    xp: 0,
    base_health: base_health,
    base_power: base_power,
    base_defense: base_defense ,
    health: base_health,
    power: base_power,
    defense: base_defense,
    energy: 5,
    is_ko: false
  ]


  player = [
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

 
# idle fight during five round 
# cypherans are preprogammed with a battle sequence
# the sequence is read to resolve round for each cypheran
# winning conditions : either the opponent cypherans is ko or player's cypheran made the most damage after the 5 rounds
# version 1 : we consider that their is only the action attack in the sequence
condition triggered_by: transaction, on: fight(opponent_address), as: [
  content:  (
            player_previous_address = Chain.get_previous_address(transaction)
            player_genesis_address = Chain.get_genesis_address(player_previous_address)
            opponent_genesis_address = Chain.get_genesis_address(String.to_hex(opponent_address))
            
            player = get_player(player_genesis_address)
            opponent = get_player(opponent_genesis_address)

            if player_genesis_address != opponent_genesis_address  do
            
              players_are_known? = player != nil && opponent != nil
              archmons_ko? = !player.archmon.is_ko && !opponent.archmon.is_ko

              players_are_known? && archmons_ko? && player.archmon.energy > 0 
           
            else 

              false 

            end

           
  )
]




actions triggered_by: transaction, on: fight(opponent_address) do

players = State.get("players")

 
  player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)

  opponent_genesis_address = Chain.get_genesis_address(String.to_hex(opponent_address))
  
   player = Map.get(players,player_genesis_address)
   opponent = Map.get(players,opponent_genesis_address)

   player_cypheran = player.archmon
   opponent_cypheran =  opponent.archmon

action_code = "fight"

player_battle_sequence = []
opponent_battle_sequence = []

 seed = State.get("random_generator_seed", Math.rem(Time.now(),Math.pow(2,32) ))


# fight over 5 rounds
# timeline to know when attack is triggered
# for version 1 both palyer and opponent attacks happens at the same time

for i in 1..5 do

  # generate random rolls
  player_attack_roll = generate_pseudo_random_roll_number(seed)

  player_defense_roll = generate_pseudo_random_roll_number(player_attack_roll.next_seed)
 
  
  opponent_attack_roll = generate_pseudo_random_roll_number(player_defense_roll.next_seed)
 
  opponent_defense_roll = generate_pseudo_random_roll_number(opponent_attack_roll.next_seed)

  seed = opponent_defense_roll.next_seed
 
# resolve attack

  player_result = resolve_player_attack( player_cypheran.power, player_attack_roll.roll_number,  opponent_cypheran, opponent_defense_roll.roll_number )
  opponent_result = resolve_player_attack( opponent_cypheran.power,opponent_attack_roll.roll_number,  player_cypheran, player_defense_roll.roll_number )

player_cypheran = opponent_result.target_cypheran
opponent_cypheran = player_result.target_cypheran

player_battle_sequence = List.append(player_battle_sequence, player_result )
opponent_battle_sequence = List.append(opponent_battle_sequence, opponent_result )
 # end fight if one or both cypherans ko

  if player_result.target_cypheran.is_ko || opponent_result.target_cypheran.is_ko do

    i = 5
    
  end

end

# update next seed 
State.set("random_generator_seed", seed)



  # keep historic of the last 10 player battle transaction
  list_battle_historic = Map.get(player,"battle_historic", [] )

  battle_info = [
    transaction_address: transaction.address,
    player_battle_sequence: player_battle_sequence,
    opponent_battle_sequence: opponent_battle_sequence
  ]

list_battle_historic = List.prepend(list_battle_historic,battle_info )

  list_size = List.size(list_battle_historic)

  

  if  list_size > 10 do

    for i in 1..10 do

      list_max_10 = List.append(list_max_10,list_battle_historic.at(i))

    end

  list_battle_historic = list_max_10


  end

    player = Map.set(player,"battle_historic", list_battle_historic)

  action = create_action(player, action_code, opponent_genesis_address, nil)

  opponent = Map.set(opponent,"archmon",opponent_cypheran )

 player_cypheran = Map.set(player_cypheran,"energy",player_cypheran.energy - 1)
  player = Map.set(player,"archmon",player_cypheran)

  player = Map.set(player,"last_action",action)

  players = Map.set(players,player_genesis_address, player)
  players = Map.set(players,opponent_genesis_address, opponent)

  State.set("players", players)

  Contract.set_content(Json.to_string(action))


end

condition triggered_by: transaction, on: feed(), as: [

 content: ( 
   player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)
  player = get_player(player_genesis_address)
  player != nil && !player.archmon.is_ko && player.archmon.energy > 0 

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

archmon = Map.set(archmon,"energy",archmon.energy - 1)
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
      if player != nil  do

         !player.archmon.is_ko  && player.archmon.health < player.archmon.base_health  && player.archmon.energy > 0
       
  
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

archmon = Map.set(archmon,"energy", archmon.energy - 1)
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
    player != nil && player.consumed_day < State.get("day", 1)) && player.archmon.energy == 0

]

actions triggered_by: transaction, on: refresh_action_points() do
  players = State.get("players")
  player_previous_address = Chain.get_previous_address(transaction)
  player_genesis_address = Chain.get_genesis_address(player_previous_address)
  player = Map.get(players,player_genesis_address)
  archmon = player.archmon
 archmon = Map.set(archmon,"energy", 5)
 player = Map.set(player,"archmon",archmon)
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
  target: target,
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

fun resolve_player_attack( cypheran_power,player_roll_number, target_cypheran, target_roll_number ) do

  attack_power = cypheran_power + player_roll_number
  target_defense = target_cypheran.defense + target_roll_number
  
  damage_done = attack_power - target_defense

  if damage_done > 0 do

    if target_cypheran.health - damage_done > 0 do

      target_cypheran = Map.set(target_cypheran, "health", target_cypheran.health - damage_done)

    else 

      target_cypheran = Map.set(target_cypheran, "health", 0)
      
      target_cypheran = Map.set(target_cypheran, "is_ko", true)

    end
  
  else 

  
  damage_done = 0


  end

  [damage_done: damage_done,
  target_cypheran: target_cypheran,
  player_roll_number: player_roll_number,
  target_roll_number: target_roll_number
  ]


end

fun level_up(archmon,add_xp) do

 archmon = Map.set(archmon,"base_health", archmon.base_health + 5)
 archmon = Map.set(archmon,"health", archmon.base_health)

 archmon = Map.set(archmon,"base_power", archmon.base_power + 1)
 archmon = Map.set(archmon,"power", archmon.base_power)

 archmon = Map.set(archmon,"base_defense", archmon.base_defense + 1)
 archmon = Map.set(archmon,"power", archmon.base_defense)

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

fun linear_congruential_generator(seed) do


end

# pseudo random roll number generator
fun generate_pseudo_random_roll_number(seed) do
  # Generate the next pseudo-random number
  # with a linear congruential generator
  a = 1664525
  c = 1013904223
  m = Math.pow(2,32)
 

   # Calculate the next seed using the LCG formula
  next_seed = Math.rem(a * seed + c, m)


  roll_number = Math.rem(next_seed, 6) + 1 # Ensures the roll number is between 1 and 6

  [roll_number: roll_number,
   next_seed:  next_seed]

end

export fun get_player_battle_historic(player_genesis_address) do
  player_genesis_address = String.to_hex(player_genesis_address)
  players = State.get("players", Map.new())

   player = Map.get(players, player_genesis_address, nil)

   battle_historic = nil

  if player != nil do
  
    battle_historic = Map.get(player,"battle_historic",[])

  end 

  battle_historic

end

export fun get_player_info(player_genesis_address) do
  player_genesis_address = String.to_hex(player_genesis_address)

  players = State.get("players", Map.new())

  
  player = Map.get(players, player_genesis_address, nil)

  if player != nil do
  archmon = player.archmon
  archmon = Map.set(archmon,"xp_to_next_level",archmon.level * 20)
  player = Map.set(player, "archmon",archmon)
  player = Map.set(player,"battlechain_mode",State.get("mode","classique"))

  end 

  player


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

export fun get_players() do

State.get("players")

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

export fun get_mode() do
State.get("mode","classique")

end

export fun ping() do

"pong"

end
