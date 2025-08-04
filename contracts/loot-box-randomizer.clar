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

(define-data-var box-counter uint u0)
(define-data-var item-counter uint u0)
(define-data-var vrf-seed uint u12345)
(define-data-var box-price uint u1000000)
(define-data-var listing-counter uint u0)
(define-data-var marketplace-fee-percent uint u5)

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

(define-private (get-next-box-id)
  (begin
    (var-set box-counter (+ (var-get box-counter) u1))
    (var-get box-counter)))

(define-private (get-next-item-id)
  (begin
    (var-set item-counter (+ (var-get item-counter) u1))
    (var-get item-counter)))

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
