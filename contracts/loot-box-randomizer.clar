(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-funds (err u101))
(define-constant err-box-not-found (err u102))
(define-constant err-already-opened (err u103))
(define-constant err-invalid-rarity (err u104))
(define-constant err-no-items (err u105))
(define-constant err-invalid-item (err u106))
(define-constant err-insufficient-items (err u107))
(define-constant err-invalid-fusion (err u108))
(define-constant err-listing-not-found (err u109))
(define-constant err-not-listing-owner (err u110))
(define-constant err-cannot-buy-own-item (err u111))
(define-constant err-listing-inactive (err u112))
(define-constant err-item-not-staked (err u113))
(define-constant err-item-already-staked (err u114))
(define-constant err-staking-period-not-met (err u115))
(define-constant err-insufficient-staking-balance (err u116))
(define-constant err-draw-not-found (err u117))
(define-constant err-draw-not-active (err u118))
(define-constant err-draw-already-ended (err u119))
(define-constant err-no-tickets-sold (err u120))
(define-constant err-invalid-prize (err u121))

(define-data-var box-counter uint u0)
(define-data-var item-counter uint u0)
(define-data-var vrf-seed uint u12345)
(define-data-var box-price uint u1000000)
(define-data-var listing-counter uint u0)
(define-data-var marketplace-fee-percent uint u5)
(define-data-var staking-pool-balance uint u0)
(define-data-var min-staking-period uint u1440)
(define-data-var base-reward-rate uint u100)
(define-data-var draw-counter uint u0)
(define-data-var default-ticket-price uint u500000)

(define-map loot-boxes uint {
  owner: principal,
  opened: bool,
  purchase-height: uint
})

(define-map box-rewards uint {
  item-id: uint,
  rarity: uint
})

(define-map items uint {
  name: (string-ascii 64),
  rarity: uint,
  value: uint,
  total-supply: uint
})

(define-map user-inventory { user: principal, item-id: uint } uint)

(define-map rarity-pools uint (list 20 uint))

(define-map fusion-recipes uint { 
  input-rarity: uint, 
  input-count: uint, 
  output-rarity: uint 
})

(define-map marketplace-listings uint {
  seller: principal,
  item-id: uint,
  price: uint,
  active: bool,
  listed-height: uint
})

(define-map staked-items { staker: principal, item-id: uint } {
  staked-at: uint,
  reward-claimed-at: uint,
  quantity: uint
})

(define-map lucky-draws uint {
  prize-type: (string-ascii 10),
  prize-id: uint,
  ticket-price: uint,
  end-height: uint,
  total-tickets: uint,
  active: bool,
  winner: (optional principal)
})

(define-map draw-tickets { draw-id: uint, ticket-number: uint } principal)
(define-map user-draw-tickets { user: principal, draw-id: uint } uint)

(define-private (get-next-box-id)
  (begin
    (var-set box-counter (+ (var-get box-counter) u1))
    (var-get box-counter)))

(define-private (get-next-item-id)
  (begin
    (var-set item-counter (+ (var-get item-counter) u1))
    (var-get item-counter)))

(define-private (get-next-draw-id)
  (begin
    (var-set draw-counter (+ (var-get draw-counter) u1))
    (var-get draw-counter)))

(define-private (get-next-listing-id)
  (begin
    (var-set listing-counter (+ (var-get listing-counter) u1))
    (var-get listing-counter)))

(define-private (generate-randomness)
  (let (
    (current-seed (var-get vrf-seed))
    (block-num stacks-block-height)
    (new-seed (+ current-seed (mod block-num u1000000)))
  )
    (var-set vrf-seed new-seed)
    new-seed))

(define-private (determine-rarity (random-value uint))
  (let ((roll (mod random-value u100)))
    (if (<= roll u1) u5
      (if (<= roll u5) u4
        (if (<= roll u15) u3
          (if (<= roll u35) u2
            u1))))))

(define-private (get-random-item-from-rarity (rarity uint) (seed uint))
  (match (map-get? rarity-pools rarity)
    pool-items 
      (if (> (len pool-items) u0)
        (some (unwrap-panic (element-at pool-items (mod seed (len pool-items)))))
        none)
    none))

(define-private (add-to-inventory (user principal) (item-id uint))
  (let (
    (current-amount (default-to u0 (map-get? user-inventory { user: user, item-id: item-id })))
  )
    (map-set user-inventory { user: user, item-id: item-id } (+ current-amount u1))
    true))

(define-private (update-item-supply (item-id uint))
  (match (map-get? items item-id)
    item-data 
      (map-set items item-id (merge item-data { total-supply: (+ (get total-supply item-data) u1) }))
    false))

(define-private (remove-from-inventory (user principal) (item-id uint) (amount uint))
  (let (
    (current-amount (default-to u0 (map-get? user-inventory { user: user, item-id: item-id })))
  )
    (if (>= current-amount amount)
      (begin
        (map-set user-inventory { user: user, item-id: item-id } (- current-amount amount))
        true)
      false)))

(define-private (validate-and-consume-item (item-id uint) (acc bool))
  (if (not acc)
    false
    (match (map-get? items item-id)
      item-data
        (let (
          (user-count (get-user-item-count tx-sender item-id))
        )
          (if (> user-count u0)
            (remove-from-inventory tx-sender item-id u1)
            false))
      false)))

(define-private (calculate-staking-rewards (staker principal) (item-id uint))
  (match (map-get? staked-items { staker: staker, item-id: item-id })
    stake-data
      (match (map-get? items item-id)
        item-data
          (let (
            (current-height stacks-block-height)
            (last-claim (get reward-claimed-at stake-data))
            (blocks-since-claim (- current-height last-claim))
            (rarity-multiplier (get rarity item-data))
            (quantity-staked (get quantity stake-data))
            (base-rate (var-get base-reward-rate))
            (reward-per-block (/ (* base-rate rarity-multiplier) u1000))
          )
            (* reward-per-block (* blocks-since-claim quantity-staked)))
        u0)
    u0))



(define-public (initialize-rarity-pools)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set rarity-pools u1 (list))
    (map-set rarity-pools u2 (list))
    (map-set rarity-pools u3 (list))
    (map-set rarity-pools u4 (list))
    (map-set rarity-pools u5 (list))
    (ok true)))

(define-public (initialize-fusion-recipes)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set fusion-recipes u1 { input-rarity: u1, input-count: u3, output-rarity: u2 })
    (map-set fusion-recipes u2 { input-rarity: u2, input-count: u3, output-rarity: u3 })
    (map-set fusion-recipes u3 { input-rarity: u3, input-count: u2, output-rarity: u4 })
    (map-set fusion-recipes u4 { input-rarity: u4, input-count: u2, output-rarity: u5 })
    (ok true)))

(define-public (add-item (name (string-ascii 64)) (rarity uint) (value uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= rarity u1) (<= rarity u5)) err-invalid-rarity)
    (let (
      (item-id (get-next-item-id))
      (current-pool (default-to (list) (map-get? rarity-pools rarity)))
    )
      (map-set items item-id {
        name: name,
        rarity: rarity,
        value: value,
        total-supply: u0
      })
      (map-set rarity-pools rarity (unwrap-panic (as-max-len? (append current-pool item-id) u20)))
      (ok item-id))))

(define-public (purchase-box)
  (let (
    (box-id (get-next-box-id))
    (price (var-get box-price))
  )
    (try! (stx-transfer? price tx-sender contract-owner))
    (map-set loot-boxes box-id {
      owner: tx-sender,
      opened: false,
      purchase-height: stacks-block-height
    })
    (ok box-id)))

(define-public (open-box (box-id uint))
  (let (
    (box-data (unwrap! (map-get? loot-boxes box-id) err-box-not-found))
  )
    (asserts! (is-eq (get owner box-data) tx-sender) err-owner-only)
    (asserts! (not (get opened box-data)) err-already-opened)
    (let (
      (random-seed (generate-randomness))
      (item-rarity (determine-rarity random-seed))
      (selected-item (unwrap! (get-random-item-from-rarity item-rarity (+ random-seed u42)) err-no-items))
    )
      (map-set loot-boxes box-id (merge box-data { opened: true }))
      (map-set box-rewards box-id { item-id: selected-item, rarity: item-rarity })
      (add-to-inventory tx-sender selected-item)
      (update-item-supply selected-item)
      (ok selected-item))))

(define-public (set-box-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set box-price new-price)
    (ok true)))

(define-public (update-vrf-seed (new-seed uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set vrf-seed new-seed)
    (ok true)))

(define-public (fuse-items (input-rarity uint) (item-ids (list 10 uint)))
  (let (
    (recipe (unwrap! (map-get? fusion-recipes input-rarity) err-invalid-fusion))
    (required-count (get input-count recipe))
    (output-rarity (get output-rarity recipe))
    (provided-count (len item-ids))
  )
    (asserts! (is-eq provided-count required-count) err-insufficient-items)
    (asserts! (< output-rarity u6) err-invalid-rarity)
    (let (
      (validation-result (fold validate-and-consume-item item-ids true))
    )
      (asserts! validation-result err-insufficient-items)
      (let (
        (random-seed (generate-randomness))
        (output-item (unwrap! (get-random-item-from-rarity output-rarity random-seed) err-no-items))
      )
        (add-to-inventory tx-sender output-item)
        (update-item-supply output-item)
        (ok output-item)))))

(define-public (list-item-for-sale (item-id uint) (price uint))
  (begin
    (asserts! (> price u0) err-insufficient-funds)
    (asserts! (> (get-user-item-count tx-sender item-id) u0) err-insufficient-items)
    (asserts! (remove-from-inventory tx-sender item-id u1) err-insufficient-items)
    (let (
      (listing-id (get-next-listing-id))
    )
      (map-set marketplace-listings listing-id {
        seller: tx-sender,
        item-id: item-id,
        price: price,
        active: true,
        listed-height: stacks-block-height
      })
      (ok listing-id))))

(define-public (purchase-listed-item (listing-id uint))
  (let (
    (listing (unwrap! (map-get? marketplace-listings listing-id) err-listing-not-found))
  )
    (asserts! (get active listing) err-listing-inactive)
    (asserts! (not (is-eq tx-sender (get seller listing))) err-cannot-buy-own-item)
    (let (
      (item-price (get price listing))
      (seller (get seller listing))
      (item-id (get item-id listing))
      (marketplace-fee (/ (* item-price (var-get marketplace-fee-percent)) u100))
      (seller-amount (- item-price marketplace-fee))
    )
      (try! (stx-transfer? marketplace-fee tx-sender contract-owner))
      (try! (stx-transfer? seller-amount tx-sender seller))
      (map-set marketplace-listings listing-id (merge listing { active: false }))
      (add-to-inventory tx-sender item-id)
      (ok item-id))))

(define-public (cancel-listing (listing-id uint))
  (let (
    (listing (unwrap! (map-get? marketplace-listings listing-id) err-listing-not-found))
  )
    (asserts! (is-eq tx-sender (get seller listing)) err-not-listing-owner)
    (asserts! (get active listing) err-listing-inactive)
    (let (
      (item-id (get item-id listing))
    )
      (map-set marketplace-listings listing-id (merge listing { active: false }))
      (add-to-inventory tx-sender item-id)
      (ok true))))

(define-public (set-marketplace-fee (new-fee-percent uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee-percent u20) err-invalid-item)
    (var-set marketplace-fee-percent new-fee-percent)
    (ok true)))

(define-public (stake-item (item-id uint) (quantity uint))
  (begin
    (asserts! (> quantity u0) err-insufficient-items)
    (asserts! (>= (get-user-item-count tx-sender item-id) quantity) err-insufficient-items)
    (asserts! (is-none (map-get? staked-items { staker: tx-sender, item-id: item-id })) err-item-already-staked)
    (asserts! (remove-from-inventory tx-sender item-id quantity) err-insufficient-items)
    (map-set staked-items { staker: tx-sender, item-id: item-id } {
      staked-at: stacks-block-height,
      reward-claimed-at: stacks-block-height,
      quantity: quantity
    })
    (ok true)))

(define-public (unstake-item (item-id uint))
  (let (
    (stake-data (unwrap! (map-get? staked-items { staker: tx-sender, item-id: item-id }) err-item-not-staked))
    (blocks-staked (- stacks-block-height (get staked-at stake-data)))
    (min-period (var-get min-staking-period))
    (quantity (get quantity stake-data))
  )
    (asserts! (>= blocks-staked min-period) err-staking-period-not-met)
    (map-delete staked-items { staker: tx-sender, item-id: item-id })
    (let (
      (current-amount (default-to u0 (map-get? user-inventory { user: tx-sender, item-id: item-id })))
    )
      (map-set user-inventory { user: tx-sender, item-id: item-id } (+ current-amount quantity)))
    (ok true)))

(define-public (claim-staking-rewards (item-id uint))
  (let (
    (stake-data (unwrap! (map-get? staked-items { staker: tx-sender, item-id: item-id }) err-item-not-staked))
    (reward-amount (calculate-staking-rewards tx-sender item-id))
    (pool-balance (var-get staking-pool-balance))
  )
    (asserts! (> reward-amount u0) err-insufficient-staking-balance)
    (asserts! (>= pool-balance reward-amount) err-insufficient-staking-balance)
    (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))
    (var-set staking-pool-balance (- pool-balance reward-amount))
    (map-set staked-items { staker: tx-sender, item-id: item-id }
      (merge stake-data { reward-claimed-at: stacks-block-height }))
    (ok reward-amount)))

(define-public (fund-staking-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set staking-pool-balance (+ (var-get staking-pool-balance) amount))
    (ok true)))

(define-public (set-staking-parameters (min-period uint) (reward-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set min-staking-period min-period)
    (var-set base-reward-rate reward-rate)
    (ok true)))

(define-public (create-draw (prize-type (string-ascii 10)) (prize-id uint) (duration-blocks uint) (ticket-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (or (is-eq prize-type "item") (is-eq prize-type "stx")) err-invalid-prize)
    (let (
      (draw-id (get-next-draw-id))
      (end-height (+ stacks-block-height duration-blocks))
    )
      (map-set lucky-draws draw-id {
        prize-type: prize-type,
        prize-id: prize-id,
        ticket-price: ticket-price,
        end-height: end-height,
        total-tickets: u0,
        active: true,
        winner: none
      })
      (ok draw-id))))

(define-public (buy-draw-ticket (draw-id uint) (quantity uint))
  (let (
    (draw (unwrap! (map-get? lucky-draws draw-id) err-draw-not-found))
    (ticket-price (get ticket-price draw))
    (total-cost (* ticket-price quantity))
    (current-tickets (get total-tickets draw))
    (user-tickets (default-to u0 (map-get? user-draw-tickets { user: tx-sender, draw-id: draw-id })))
  )
    (asserts! (get active draw) err-draw-not-active)
    (asserts! (< stacks-block-height (get end-height draw)) err-draw-already-ended)
    (try! (stx-transfer? total-cost tx-sender contract-owner))
    (map-set lucky-draws draw-id (merge draw { total-tickets: (+ current-tickets quantity) }))
    (map-set user-draw-tickets { user: tx-sender, draw-id: draw-id } (+ user-tickets quantity))
    (map-set draw-tickets { draw-id: draw-id, ticket-number: (+ current-tickets u1) } tx-sender)
    (ok (+ current-tickets quantity))))

(define-public (execute-draw (draw-id uint))
  (let (
    (draw (unwrap! (map-get? lucky-draws draw-id) err-draw-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (get active draw) err-draw-not-active)
    (asserts! (>= stacks-block-height (get end-height draw)) err-draw-not-active)
    (asserts! (> (get total-tickets draw) u0) err-no-tickets-sold)
    (let (
      (random-seed (generate-randomness))
      (winning-ticket (+ u1 (mod random-seed (get total-tickets draw))))
      (winner (unwrap! (map-get? draw-tickets { draw-id: draw-id, ticket-number: winning-ticket }) err-draw-not-found))
      (prize-type (get prize-type draw))
      (prize-id (get prize-id draw))
    )
      (map-set lucky-draws draw-id (merge draw { active: false, winner: (some winner) }))
      (if (is-eq prize-type "item")
        (add-to-inventory winner prize-id)
        (try! (as-contract (stx-transfer? prize-id tx-sender winner))))
      (ok winner))))

(define-public (cancel-draw (draw-id uint))
  (let (
    (draw (unwrap! (map-get? lucky-draws draw-id) err-draw-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (get active draw) err-draw-not-active)
    (map-set lucky-draws draw-id (merge draw { active: false }))
    (ok true)))

(define-read-only (get-box-info (box-id uint))
  (map-get? loot-boxes box-id))

(define-read-only (get-box-reward (box-id uint))
  (map-get? box-rewards box-id))

(define-read-only (get-item-info (item-id uint))
  (map-get? items item-id))

(define-read-only (get-user-item-count (user principal) (item-id uint))
  (default-to u0 (map-get? user-inventory { user: user, item-id: item-id })))

(define-read-only (get-current-box-price)
  (var-get box-price))

(define-read-only (get-total-boxes)
  (var-get box-counter))

(define-read-only (get-total-items)
  (var-get item-counter))

(define-read-only (get-rarity-pool (rarity uint))
  (map-get? rarity-pools rarity))

(define-read-only (get-current-vrf-seed)
  (var-get vrf-seed))

(define-read-only (preview-rarity-roll (seed uint))
  (let ((roll (mod seed u100)))
    { roll: roll, rarity: (determine-rarity seed) }))

(define-read-only (get-contract-owner)
  contract-owner)

(define-read-only (is-box-opened (box-id uint))
  (match (map-get? loot-boxes box-id)
    box-data (get opened box-data)
    false))

(define-read-only (get-box-owner (box-id uint))
  (match (map-get? loot-boxes box-id)
    box-data (some (get owner box-data))
    none))

(define-read-only (simulate-opening)
  (let (
    (test-seed (+ (var-get vrf-seed) stacks-block-height))
    (test-rarity (determine-rarity test-seed))
  )
    { 
      seed: test-seed,
      rarity: test-rarity,
      available-items: (get-rarity-pool test-rarity)
    }))

(define-read-only (get-fusion-recipe (input-rarity uint))
  (map-get? fusion-recipes input-rarity))

(define-read-only (can-user-fuse (user principal) (input-rarity uint))
  (match (map-get? fusion-recipes input-rarity)
    recipe
      (let (
        (required-count (get input-count recipe))
        (item-count (fold count-rarity-items (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) { user: user, rarity: input-rarity, count: u0 }))
      )
        (>= (get count item-count) required-count))
    false))

(define-private (count-rarity-items (item-id uint) (acc { user: principal, rarity: uint, count: uint }))
  (match (map-get? items item-id)
    item-data
      (if (is-eq (get rarity item-data) (get rarity acc))
        (merge acc { count: (+ (get count acc) (get-user-item-count (get user acc) item-id)) })
        acc)
    acc))

(define-read-only (get-marketplace-listing (listing-id uint))
  (map-get? marketplace-listings listing-id))

(define-read-only (get-active-listings-count)
  (var-get listing-counter))

(define-read-only (get-marketplace-fee-percent)
  (var-get marketplace-fee-percent))

(define-read-only (get-item-market-price (item-id uint))
  (let (
    (total-listings (var-get listing-counter))
  )
    (fold find-lowest-price (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) { target-item: item-id, lowest-price: u999999999 })))

(define-private (find-lowest-price (listing-id uint) (acc { target-item: uint, lowest-price: uint }))
  (match (map-get? marketplace-listings listing-id)
    listing
      (if (and (get active listing) (is-eq (get item-id listing) (get target-item acc)))
        (if (< (get price listing) (get lowest-price acc))
          (merge acc { lowest-price: (get price listing) })
          acc)
        acc)
    acc))

(define-read-only (is-listing-active (listing-id uint))
  (match (map-get? marketplace-listings listing-id)
    listing (get active listing)
    false))

(define-read-only (get-staking-info (staker principal) (item-id uint))
  (map-get? staked-items { staker: staker, item-id: item-id }))

(define-read-only (get-pending-staking-rewards (staker principal) (item-id uint))
  (calculate-staking-rewards staker item-id))

(define-read-only (get-staking-pool-balance)
  (var-get staking-pool-balance))

(define-read-only (get-staking-parameters)
  { 
    min-period: (var-get min-staking-period),
    base-reward-rate: (var-get base-reward-rate)
  })

(define-read-only (is-item-staked (staker principal) (item-id uint))
  (is-some (map-get? staked-items { staker: staker, item-id: item-id })))

(define-read-only (get-total-staking-value (staker principal))
  (let (
    (total-items (var-get item-counter))
  )
    (fold calculate-user-staking-value (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) { user: staker, total-value: u0 })))

(define-private (calculate-user-staking-value (item-id uint) (acc { user: principal, total-value: uint }))
  (match (map-get? staked-items { staker: (get user acc), item-id: item-id })
    stake-data
      (match (map-get? items item-id)
        item-data
          (let (
            (quantity (get quantity stake-data))
            (item-value (get value item-data))
            (stake-value (* quantity item-value))
          )
            (merge acc { total-value: (+ (get total-value acc) stake-value) }))
        acc)
    acc))

(define-read-only (get-draw-info (draw-id uint))
  (map-get? lucky-draws draw-id))

(define-read-only (get-user-draw-tickets (user principal) (draw-id uint))
  (default-to u0 (map-get? user-draw-tickets { user: user, draw-id: draw-id })))

(define-read-only (get-total-draws)
  (var-get draw-counter))

(define-read-only (is-draw-active (draw-id uint))
  (match (map-get? lucky-draws draw-id)
    draw (and (get active draw) (< stacks-block-height (get end-height draw)))
    false))

(define-read-only (get-draw-winner (draw-id uint))
  (match (map-get? lucky-draws draw-id)
    draw (get winner draw)
    none))

(define-read-only (calculate-draw-pool (draw-id uint))
  (match (map-get? lucky-draws draw-id)
    draw 
      (let (
        (total-tickets (get total-tickets draw))
        (ticket-price (get ticket-price draw))
      )
        (* total-tickets ticket-price))
    u0))
