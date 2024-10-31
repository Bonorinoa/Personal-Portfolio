extensions [table]
globals [ AD AS ] ; add supply shock

breed [consumers consumer]
breed [producers producer]

consumers-own [
  wealth ; f(initial endowment, wage)
  wage ; amount paid every 24 hours to consumer
  ;expenses ; autonomous consumption (things you would buy even with no income and taxes)
  demand ; how much to consume at target-market ~ f(disposable income, utility, price, quantity)
  unmet-demand ; amount the consumer tried to buy but there was not enough supply/stock
  debt ; negative wealth

  price-expectations ; one of {up, stay, down}
  last-price-paid ; memory

  ;; spatial variables
  steps-to-market ; distance measure
  target-market ; chosen market at period t. Determined by determine-target-market
  origin-x ; x-cor of house
  origin-y ; y-cor of house
  state ; "moving-to-market", "at-market", "returning", "at-origin"

  ticks-at-market ; to bound waiting time at the market
  ticks-at-origin ; to bound waiting time at home
]

producers-own [
  ;profit ; f(price, output, costs)
  output ; how much to supply to target-market
  ;capital
  ;technology ; the function that takes in capital and produces output (often a convex function with diminishing marginal returns)
  capacity ; output upper bound
  costs ; costs from selling output. Could be a function affected by supply shocks and other exogenous factors in future versions
  unmet-supply

  demand-expectations ; one of {up, stay, down}
  last-demand-supplied ; memory


  ;; spatial variables
  steps-to-market
  target-market
  origin-x
  origin-y
  state ; "moving-to-market", "at-market", "returning", "at-origin"

  ticks-at-market
  ticks-at-origin
]

patches-own [
  quantity-available
  unit-price
  market-capacity
]


to setup
  clear-all

  set-default-shape turtles "person" ; For a more realistic representation

  ; Global economic indicators
  set AD 0
  set AS 0 ; some initial supply must exist for a market to exist

  ; Create markets in designated regions (as before)
  create-markets

  ; Create consumers with updated income and wealth distributions
  create-households

  ; Create producers with realistic costs and production levels
  create-factories


  reset-ticks
end


;;#### Main procedures ####
to create-markets

  ask n-of num-regions patches [
    ask n-of num-markets-per-region patches in-radius 8 [
      set pcolor red
      set plabel (word pxcor " " pycor)
      set quantity-available 0
      set unit-price 10 ; Initial price
      set market-capacity 150
    ]
  ]
end

;sprout is a patch-only primitive that allows us to ask patches to create new turtles.

;create households and consumers that leave from it
;; default 5 households with 3 consumers each
to create-households
  ask n-of num-households patches [
    set pcolor blue ; households are blue
    sprout-consumers num-consumers [
      ;setxy random-pxcor random-pycor
      set size 1.5
      set color blue
      set origin-x pxcor
      set origin-y pycor
      set state "moving-to-market"
      set ticks-at-market 0


      set wealth random-normal 500 50 ; Assume some variability around the median
      set wage random-normal 300 15

      set price-expectations one-of ["up" "stay" "down"]
      set steps-to-market 0
      set demand 0
      set target-market nobody
      ;other state variables like
    ]
  ]
end



;create factories and producers that leave from it
;; default 4 factories with 2 producers each
to create-factories
  ask n-of num-factories patches [
    set pcolor green
    sprout-producers num-producers [
      ;setxy random-pxcor random-pycor
      set size 1.5
      set color green
      set origin-x pxcor
      set origin-y pycor
      set state "moving-to-market"
      set ticks-at-market 0
      set target-market nobody

      ; economic variables
      set output 0
      set demand-expectations one-of ["up" "stay" "down"]
      set steps-to-market 0

      set capacity 150 ; global initial max for now
    ]
  ]
end


;; ##### MOVEMENT #####
; search for closest market
to determine-target-market
  let search-radius 10

  ask consumers [
    let local-markets patches in-radius search-radius with [pcolor = red]
    ifelse any? local-markets [
      let closest-market min-one-of local-markets [distance myself]
      set target-market closest-market

      if ticks > 24 [
        let avg-price mean [unit-price] of local-markets
        if [unit-price] of target-market > avg-price [
          let cheaper-market min-one-of local-markets [unit-price]
          if cheaper-market != nobody [
            set target-market cheaper-market
          ]
        ]
      ]
    ] [
      set target-market min-one-of patches with [pcolor = red] [distance myself]
    ]
  ]

  ask producers [
    let local-markets patches in-radius search-radius with [pcolor = red]
    ifelse any? local-markets [
      let closest-market min-one-of local-markets [distance myself]
      set target-market closest-market

      if ticks > 24 or costs > mean [costs] of producers [
        let target-quantity [quantity-available] of target-market
        let high-demand-market min-one-of local-markets with [quantity-available < target-quantity] [quantity-available]
        if high-demand-market != nobody [
          set target-market high-demand-market
        ]
      ]
    ] [
      set target-market min-one-of patches with [pcolor = red] [distance myself]
    ]
  ]
end



to move-towards-market
  ask turtles [
    if state = "moving-to-market" [
      face target-market
      fd 1
      if at-market? [ set state "at-market" ]
    ]
  ]
end


to return-to-origin
  ask turtles with [state = "returning"] [
    facexy origin-x origin-y
    ifelse distancexy origin-x origin-y > 1 [
      fd 1
    ] [
      set state "at-origin"
    ]
  ]
end

to return-to-market
  ask turtles with [state = "at-origin"][
    set ticks-at-origin ticks-at-origin + 1
    if ticks-at-origin >= 10 [
      set state "moving-to-market"
      set ticks-at-origin 0
      determine-target-market
    ]
  ]
end

;;###############################

to update-market-time
  ask turtles with [state = "at-market"] [
    set ticks-at-market ticks-at-market + 1
    if ticks-at-market >= 5 [ ; 5 ticks = 2 hours
      set state "returning"
      set ticks-at-market 0 ; Reset counter for next market visit
    ]
  ]
end

to-report at-market?
  report [pcolor] of patch-here = red  ;; market patches are red
end


;; ###### CONSUMER #######

;consumption decision
;;Consumer decision-making based on wealth, income, expenses, and price expectations
to consumer-decision
  ask consumers [
    ; Adjust demand based on previous unmet-demand and current price expectations
    let adjustment-weight 0
    ifelse unmet-demand > 0 [
      if price-expectations = "down" [ set adjustment-weight int(unmet-demand * 0.3)  ]
      if price-expectations = "up" [ set adjustment-weight int(unmet-demand * 0.7)  ]
      if price-expectations = "stay" [ set adjustment-weight int(unmet-demand * 0.5)  ]
      set demand min (list (demand + adjustment-weight) 10)
    ] [ set demand 10 ]

    if at-market? and ticks-at-market < 1 [
      let market-price [unit-price] of patch-here
      let available [quantity-available] of patch-here
      ifelse available > 0 and debt < 2 * wealth [
        let quantity-to-consume min list demand available

        ask patch-here [ set quantity-available (available - quantity-to-consume) ]

        set wealth wealth - (quantity-to-consume * market-price)
        set last-price-paid market-price
        set debt (ifelse-value (wealth < 0) [abs(wealth)] [debt])
        set wealth (ifelse-value (wealth < 0) [0] [wealth])
        set AD AD + quantity-to-consume
      ] [
        set unmet-demand unmet-demand + demand
        set debt debt * 0.5
      ]
      set ticks-at-market 1
    ]
  ]
end


;;####################


;; ###### PRODUCER #####

;production decision
;;Producer decision-making based on costs and demand expectations
to producer-decision
  ask producers [
    let supply-adjustment-weight 0
    ifelse unmet-supply > 0 [
      if demand-expectations = "down" [ set supply-adjustment-weight int(unmet-supply * 0.3)  ]
      if demand-expectations = "up" [ set supply-adjustment-weight int(unmet-supply * 0.7)  ]
      if demand-expectations = "stay" [ set supply-adjustment-weight int(unmet-supply * 0.5)  ]
      set output max (list (output - supply-adjustment-weight) 5)
    ] [ set output 10 ]

    if at-market? and ticks-at-market < 1 [
      let supply output
      let market-info [list quantity-available market-capacity] of patch-here
      let new-quantity-available (item 0 market-info + supply)
      ifelse new-quantity-available <= item 1 market-info [
        ask patch-here [ set quantity-available new-quantity-available ]
        ;set unmet-supply 0
        set last-demand-supplied output
        set costs last-demand-supplied * [unit-price] of patch-here
      ] [
        set unmet-supply unmet-supply + (new-quantity-available - item 1 market-info)
        ask patch-here [ set quantity-available item 1 market-info ]
      ]
      set ticks-at-market 1
    ]
    set AS AS + output
  ]
end


;;################


;; ##### MARKET #####

; Adjust markets' prices based on supply and demand
;; law of demand: prices tend to rise when demand exceeds supply (unmet demand) and fall when supply exceeds demand (unmet supply)
;; KEEP WORKING ON PRICE ADJUSTMENT LOGIC

to new-price
  ask patches with [pcolor = red] [
    ; Calculate local demand and supply, ensuring they are at least 1 to avoid division by zero
    let local-demand max list 1 sum [demand] of consumers-here
    let local-supply max list 1 sum [output] of producers-here  ; Use max to ensure non-zero supply
    let local-unmet-demand sum [unmet-demand] of consumers-here
    let local-unmet-supply sum [unmet-supply] of producers-here

    ; Adjust prices based on local demand-supply balance
    ifelse local-demand > local-supply [
      ; Demand exceeds supply, increase price by up to 2%, scaled by the ratio of unmet demand to total demand
      let excess-demand-ratio local-unmet-demand / local-demand
      set unit-price unit-price * (1 + 0.02 * excess-demand-ratio)
      show (word "Increase price")
    ] [
      ; Supply exceeds demand, decrease price by up to 5%, scaled by the ratio of unmet supply to total supply
      let excess-supply-ratio local-unmet-supply / local-supply
      set unit-price unit-price * (1 - 0.05)
      show (word "Decrease price")
    ]

  ]

  ; Debugging and logging
  show (word "New average price = " mean [unit-price] of patches with [pcolor = red])
end


;; Reporter to collect individual market prices by ID
to-report collect-market-prices
  ; Initialize an empty list for prices
  let prices []

  ; Ask each market patch to append its coordinates and price to the list
  ask patches with [pcolor = red] [
    let id (list pxcor pycor)  ; Create a list of this patch's coordinates
    let price precision unit-price 3 ; Get the unit price for this patch
    set prices fput (list id price) prices  ; Add the coordinate-price pair to the list
  ]

  ; Output the complete list of prices and IDs
  report prices
end


to-report calculate-average-price
  ; Calculate mean of unit-price over all market patches
  let market-patches patches with [pcolor = red]
  ifelse any? market-patches [
    report mean [unit-price] of market-patches
  ] [
    report 0  ; Report 0 if no market patches to avoid errors
  ]
end





; submodel to dynamically change expectations based on last price paid and aggregated price level (average of all markets)
to adjust-expectations
  ask consumers [
    ; competitors are raising their prices relative to consumer's market, then it will expect it to go up.
    if last-price-paid - mean [unit-price] of patches with [pcolor = red] < 0 [
      set price-expectations "up"
    ]
    if last-price-paid - mean [unit-price] of patches with [pcolor = red] = 0 [
      set price-expectations "stay"
    ]
    ; consumer's market's price is higher than average, it should stay or drop
    if last-price-paid - mean [unit-price] of patches with [pcolor = red] > 0 [
      set price-expectations "down"
    ]
  ]

  ask producers [
    if last-demand-supplied - mean [demand] of consumers < 0 [
      set demand-expectations "up"
    ]
    if last-demand-supplied - mean [demand] of consumers = 0 [
      set demand-expectations "stay"
    ]
    if last-demand-supplied - mean [demand] of consumers > 0 [
      set demand-expectations "down"
    ]
  ]

end




;#################

; Reporter for counting consumers expecting prices to go up
to-report num-expect-up
  report count consumers with [price-expectations = "up"]
end

; Reporter for counting consumers expecting prices to stay the same
to-report num-expect-stay
  report count consumers with [price-expectations = "stay"]
end

; Reporter for counting consumers expecting prices to go down
to-report num-expect-down
  report count consumers with [price-expectations = "down"]
end


to demand-expectations-plot
  set-current-plot "Producer Demand Expectations"
  clear-plot
  let counts table:counts [ demand-expectations ] of producers
  let expectations sort table:keys counts
  let n length expectations
  set-plot-x-range 0 n
  let step 0.05 ; tweak this to leave no gaps
  (foreach expectations range n [ [s i] ->
    let y table:get counts s
    let c hsb (i * 360 / n) 50 75
    create-temporary-plot-pen s
    set-plot-pen-mode 1 ; bar mode
    set-plot-pen-color c
    foreach (range 0 y step) [ _y -> plotxy i _y ]
    set-plot-pen-color black
    plotxy i y
    set-plot-pen-color c ; to get the right color in the legend
  ])
end

to price-expectations-plot
  set-current-plot "Consumer Price Expectations"
  clear-plot
  let counts table:counts [ price-expectations ] of consumers
  let expectations sort table:keys counts
  let n length expectations
  set-plot-x-range 0 n
  let step 0.05 ; tweak this to leave no gaps
  (foreach expectations range n [ [s i] ->
    let y table:get counts s
    let c hsb (i * 360 / n) 50 75
    create-temporary-plot-pen s
    set-plot-pen-mode 1 ; bar mode
    set-plot-pen-color c
    foreach (range 0 y step) [ _y -> plotxy i _y ]
    set-plot-pen-color black
    plotxy i y
    set-plot-pen-color c ; to get the right color in the legend
  ])
end




;;################################

to go

  ; search for markets
  determine-target-market
  move-towards-market


  ; produer must supply first before interaction is possible
  producer-decision


  ; given supply, consumer demands s.t. budget constraints
  consumer-decision


  ;adjust-market-prices
  new-price



  update-market-time



  return-to-origin



  adjust-expectations


  demand-expectations-plot
  price-expectations-plot


  ; distribute income every 24 hours
  if ticks mod 24 = 0 [
    ask consumers [ set wealth wealth + wage ]
  ]


  return-to-market

  tick
  if ticks >= 5040 [ stop ] ; hours in one month
end
@#$#@#$#@
GRAPHICS-WINDOW
670
19
1086
436
-1
-1
8.0
1
10
1
1
1
0
0
0
1
-25
25
-25
25
1
1
1
ticks
30.0

BUTTON
1142
189
1246
249
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1266
190
1375
249
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
14
26
321
213
Market price Distribution
Market
Market price
0.0
10.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 1 -2674135 true "set-plot-y-range 0 100\n" "clear-plot  ; Clears the plot each tick for updated data\nask patches with [pcolor = red] [\n    plot unit-price  ; Use patch's x-coordinate as the x-axis value\n  ]"

PLOT
15
231
326
415
Producer output Distribution
Producers
Supply
0.0
10.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 1 -11085214 true "set-plot-y-range 0 1000\n" "clear-plot  ; Clears the plot each tick for updated data\nask producers [\n  plotxy who output  ; ‘who’ gives the turtle ID, and ‘wealth’ is the variable for wealth\n]"

PLOT
1104
267
1427
449
Avg price
ticks
price
0.0
100.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot min list 1000 mean [unit-price] of patches with [pcolor = red]"

SLIDER
1268
24
1423
57
num-markets-per-region
num-markets-per-region
1
4
2.0
1
1
NIL
HORIZONTAL

SLIDER
1102
78
1251
111
num-households
num-households
0
10
3.0
1
1
NIL
HORIZONTAL

SLIDER
1095
132
1249
165
num-factories
num-factories
0
5
3.0
1
1
NIL
HORIZONTAL

PLOT
337
232
659
419
Consumer debt distribution
ticks
Debt level
0.0
10.0
0.0
1000.0
true
false
"" ""
PENS
"default" 1.0 1 -2674135 true "set-plot-y-range 0 1000\n" "clear-plot  ; Clears the plot each tick for updated data\nask consumers [\n  plotxy who debt  ; ‘who’ gives the turtle ID, and ‘wealth’ is the variable for wealth\n]"

PLOT
334
28
662
214
Consumer wealth Distribution
Consumers
Avg Income
0.0
10.0
0.0
1000.0
true
false
"" ""
PENS
"default" 1.0 1 -11033397 true "set-plot-y-range 0 1000" "clear-plot  ; Clears the plot each tick for updated data\nask consumers [\n  plotxy who wealth  ; ‘who’ gives the turtle ID, and ‘wealth’ is the variable for wealth\n]"

SLIDER
1265
78
1415
111
num-consumers
num-consumers
0
4
2.0
1
1
NIL
HORIZONTAL

SLIDER
1101
23
1252
56
num-regions
num-regions
1
4
2.0
1
1
NIL
HORIZONTAL

SLIDER
1263
133
1419
166
num-producers
num-producers
0
5
3.0
1
1
NIL
HORIZONTAL

PLOT
386
446
749
648
Producer Demand Expectations
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"default" 1.0 1 -11085214 true "demand-expectations-plot" ""

PLOT
12
449
371
649
Consumer Price Expectations
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"default" 1.0 1 -11033397 true "price-expectations-plot" ""

@#$#@#$#@
# Purpose

The model simulates the effects of heterogeneous expectations on market prices and inflation within a local economy framework. It seeks to understand how individual differences in perception and reaction to economic conditions can collectively influence broader economic indicators like inflation and market prices.

# Entities, State Variables, and Scales

All numerical variables are non-negative, bounded below by 0

**Agents**:
  - Consumers (Households) -> Variables: wealth, labor, expenses, demand, price-expectations, steps-to-market, etc.
  - Producers (Factories) -> Variables: profit, output, capital, technology, costs, steps-to-market, etc.

**Environment**:
  - Market patches (Red patches)
  - Variables: quantity-available, unit-price, market-capacity

**Scales**:

The model operates on a discrete time scale (ticks), with spatial dimensions represented by the market patches where agents interact. The landscape is 25 x 25 with the origin at the center, with patch sizes of 8.

## Markets

Each market is represented as a patch. One market holds information about one good/service. Since no market has been supplied at tick 1, quantity available is initialized to 0. In this version of the model, there is only one good/service so we can interpret the red patches as mini markets that all sell the same good. We use the spatial capabilities of NetLogo to create "regions of markets" and capture local competition between mini markets.

Quantity available updates with turtles' visits to the market based on last period quantity, current period supply, current period demand (i.e., Inventory + Incoming Supply - Incoming demand). Price per unit updates each period based on changes in supply and demand. Note that many producers can interact with same market (i.e., decide to sell the same good/service). The interesting thing here is that the distribution of quantities and prices for the same good (all mini markets) will not necessarily be uniform at the end of the simulation. This skewness might results from geographic competitive advantage (most consumers/producers closer to some mini markets or one particular region), or heteregoneous consumption/production functions driven by changes in expectations.

Distance at market is relevant because the decision of which market to go after tick 1 will be mostly by the prices (which were unknown to the agents until they reached the market). So, since each market will have heterogenous interactions different prices will arise over time. Consumers choose the market that is closest (so will stay within region) and has lowest price (allowing for withing region competition of markets). Since prices change over time, chosen target market could be allowed to change as well.

### Process Overview and Scheduling

The simulation progresses through discrete time steps (ticks), where agents determine their target markets, move towards or return from markets based on their states, and engage in economic activities such as consumption and production. 

1. Market Search and Movement: Agents determine their target market based on proximity and expected utility.
2. Production and Consumption Decisions: Based on current market conditions and individual expectations.
3. Market Interaction: Exchange of goods and adjustment of market prices.
4. Outcome Assessment: Agents assess outcomes and update their expectations and strategies.


## Design Concepts

Basic Principles: Underlying the simulation is the principle of supply and demand, with additional considerations for economic theories like utility maximization (for consumers) and profit maximization (for producers). Spatial dynamics introduce elements of transportation costs and access to markets.

Emergence: The model allows for the emergence of market equilibria, wealth distributions, and spatial economic structures (e.g., market hotspots) from the bottom-up interactions of agents with each other and the environment. Market prices and inflation rates emerge from the interactions among consumers and producers, reflecting the aggregated outcomes of decentralized decision-making processes influenced by individual expectations and capacities.

Adaptation: Agents adapt their behavior based on price expectations, market conditions (e.g., availability of goods), and personal economic states (e.g., wealth and demand levels).

Objectives: Consumers want to buy and producers want to sell.

Learning: Agents modify their price expectations based on past experiences and adjust their strategies accordingly. This model does not implement explicit learning algorithms but assumes adaptive expectations. That is, the agents decide how much to consumer/produce each time they return to origin purely based on heuristics of the sort "if this is the 3rd time my demand is not met, I am changing markets." or "if the cost of my consumption is greater than my some fraction of my disposable income, then search for a new market with lower prices (thus trading off distance for monetary costs)"

Prediction: Not explicitly modeled, but implied through agents' price expectations and demand forecasting.

Sensing: sensei

Interaction: Economic transactions at markets represent the primary form of interaction. Consumers and producers interact within markets, where exchange processes determine the dynamics of supply, demand, and pricing.

Stochasticity: Random elements are introduced in agent attributes (e.g., initial wealth, production costs) and decisions (e.g., price expectations), reflecting real-world uncertainties. Moreover, white noise is introduced randomly to simulate unexpected supply shocks.

Collectives: Markets act as collectives where individual decisions and strategies aggregate to produce collective outcomes like average market prices and total market demand..

Observation: Key observations include the fluctuations in AD and AS, price levels across different markets, and changes in agents' wealth distributions.


## Details

Initialization: The simulation initializes with a predefined number of consumers and producers distributed across the landscape, each with randomly assigned attributes. Markets are established in specific locations.

Input Data: No external input data is required; the model runs on parameters defined within the NetLogo environment.

Environment: A 25x25 grid centered at the origin. Each patch represents an hour in the economy (i.e., it takes an hour to "cross" a patch). Thus the maximum possible distance in which a market and a turtle can be apart is around 71 patches (via pythagoras) or 71 hours of travel. (right?)

### Submodels

**Price Adjustment Mechanism**:
 - Prices in markets adjust according to the balance of supply and demand, influenced by collective agent expectations.

**Inflation Estimation**:
 - A proposed submodel for future development, to calculate inflation based on changes in price levels over time.

**Movement and Interaction**: at-market?, determine-target-market, move-towards-market, return-to-origin, return-to-market, update-market-time

**Reporters**: period-demand, period-supply

## Future work

- Design price mechanism. Do I use AD and AS, or unmet demand and supply?
- Write procedure for price adjustment
- Plot price changes over time
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="consumer-experiment" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="5024"/>
    <exitCondition>precision mean [unit-price] of patches with [pcolor = red] 3 &lt; 0.001 and ticks &gt; 1000</exitCondition>
    <metric>num-expect-up</metric>
    <metric>num-expect-stay</metric>
    <metric>num-expect-down</metric>
    <enumeratedValueSet variable="num-markets-per-region">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-regions">
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="num-consumers" first="1" step="2" last="6"/>
    <enumeratedValueSet variable="num-factories">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-producers">
      <value value="3"/>
    </enumeratedValueSet>
    <steppedValueSet variable="num-households" first="1" step="1" last="4"/>
  </experiment>
  <experiment name="market-experiment" repetitions="1" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>collect-market-prices</metric>
    <metric>calculate-average-price</metric>
    <steppedValueSet variable="num-markets-per-region" first="1" step="1" last="4"/>
    <steppedValueSet variable="num-regions" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="num-consumers">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-factories">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-producers">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-households">
      <value value="2"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
