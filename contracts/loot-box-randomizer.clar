(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-funds (err u101))
(define-constant err-box-not-found (err u102))
(define-constant err-already-opened (err u103))
(define-constant err-invalid-rarity (err u104))
(define-constant err-no-items (err u105))
(define-constant err-invalid-item (err u106))

(define-data-var box-counter uint u0)
(define-data-var item-counter uint u0)
(define-data-var vrf-seed uint u12345)
(define-data-var box-price uint u1000000)

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

(define-private (get-next-box-id)
  (begin
    (var-set box-counter (+ (var-get box-counter) u1))
    (var-get box-counter)))

(define-private (get-next-item-id)
  (begin
    (var-set item-counter (+ (var-get item-counter) u1))
    (var-get item-counter)))

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

(define-public (initialize-rarity-pools)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set rarity-pools u1 (list))
    (map-set rarity-pools u2 (list))
    (map-set rarity-pools u3 (list))
    (map-set rarity-pools u4 (list))
    (map-set rarity-pools u5 (list))
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
