;; Gaming Loot Box Economy Contract
;; Enables creator royalties for rare game items and skins

;; Error constants
(define-constant ERR-UNAUTHORIZED-USER (err u100))
(define-constant ERR-ITEM-DOES-NOT-EXIST (err u101))
(define-constant ERR-PARAMETER-ERROR (err u102))
(define-constant ERR-ALREADY-MINTED (err u103))
(define-constant ERR-WALLET-INSUFFICIENT (err u104))
(define-constant ERR-NO-LOOT-REWARDS (err u105))
(define-constant ERR-INVALID-OWNER (err u106))

;; Constants
(define-constant MAX-CREATOR-ROYALTY u400) ;; 40%
(define-constant LOOT-BASIS u1000) ;; 100% = 1000

;; Data structures
(define-map game-items
  { item-id: uint }
  {
    item-name: (string-utf8 128),
    lead-designer: principal,
    current-owner: principal,
    market-value: uint,
    creator-royalty: uint,
    minted: bool,
    tradeable: bool
  }
)

(define-map developers
  { item-id: uint, developer: principal }
  { creation-share: uint, specialty: (string-ascii 32) }
)

(define-map loot-rewards
  { item-id: uint, developer: principal }
  { reward-balance: uint }
)

;; Store list of developers for each item
(define-map item-developers
  { item-id: uint }
  { developers: (list 50 principal) }
)

(define-data-var next-item-id uint u1)

;; Create new game item
(define-public (create-item 
                (item-name (string-utf8 128))
                (market-value uint)
                (creator-royalty uint))
  (let ((item-id (var-get next-item-id)))
    ;; Validate inputs
    (asserts! (> market-value u0) ERR-PARAMETER-ERROR)
    (asserts! (<= creator-royalty MAX-CREATOR-ROYALTY) ERR-PARAMETER-ERROR)
    (asserts! (> (len item-name) u0) ERR-PARAMETER-ERROR)
    
    ;; Create game item
    (map-set game-items
      { item-id: item-id }
      {
        item-name: item-name,
        lead-designer: tx-sender,
        current-owner: tx-sender,
        market-value: market-value,
        creator-royalty: creator-royalty,
        minted: false,
        tradeable: true
      })
    
    ;; Add lead designer as primary developer
    (map-set developers
      { item-id: item-id, developer: tx-sender }
      { creation-share: LOOT-BASIS, specialty: "lead-designer" })
    
    ;; Initialize developer list
    (map-set item-developers
      { item-id: item-id }
      { developers: (list tx-sender) })
    
    ;; Increment counter
    (var-set next-item-id (+ item-id u1))
    (ok item-id)))

;; Add game developer to item creation
(define-public (add-developer
                (item-id uint)
                (developer principal)
                (creation-share uint)
                (specialty (string-ascii 32)))
  (let ((item (unwrap! (map-get? game-items { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST))
        (designer-data (unwrap! (map-get? developers { item-id: item-id, developer: (get lead-designer item) }) ERR-ITEM-DOES-NOT-EXIST))
        (updated-designer-share (- (get creation-share designer-data) creation-share))
        (current-developers (get developers (unwrap! (map-get? item-developers { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST))))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (is-eq tx-sender (get lead-designer item)) ERR-UNAUTHORIZED-USER)
    (asserts! (not (get minted item)) ERR-ALREADY-MINTED)
    (asserts! (> creation-share u0) ERR-PARAMETER-ERROR)
    (asserts! (<= creation-share (get creation-share designer-data)) ERR-PARAMETER-ERROR)
    (asserts! (not (is-eq developer tx-sender)) ERR-PARAMETER-ERROR) ;; Can't add self
    (asserts! (> (len specialty) u0) ERR-PARAMETER-ERROR)
    
    ;; Add developer
    (map-set developers
      { item-id: item-id, developer: developer }
      { creation-share: creation-share, specialty: specialty })
    
    ;; Update lead designer's share
    (map-set developers
      { item-id: item-id, developer: (get lead-designer item) }
      { creation-share: updated-designer-share, specialty: "lead-designer" })
    
    ;; Add to developer list if not already present
    (map-set item-developers
      { item-id: item-id }
      { developers: (unwrap! (as-max-len? (append current-developers developer) u50) ERR-PARAMETER-ERROR) })
    
    (ok true)))

;; Mint item from loot box
(define-public (mint-from-lootbox (item-id uint))
  (let ((item (unwrap! (map-get? game-items { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST))
        (value (get market-value item)))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (get tradeable item) ERR-PARAMETER-ERROR)
    (asserts! (not (get minted item)) ERR-ALREADY-MINTED)
    (asserts! (>= (stx-get-balance tx-sender) value) ERR-WALLET-INSUFFICIENT)
    
    ;; Transfer minting cost to contract
    (try! (stx-transfer? value tx-sender (as-contract tx-sender)))
    
    ;; Mark as minted and set current owner
    (map-set game-items
      { item-id: item-id }
      (merge item { 
        minted: true,
        current-owner: tx-sender
      }))
    
    ;; Pay lead designer
    (let ((lead-designer (get lead-designer item)))
      (as-contract (try! (stx-transfer? value tx-sender lead-designer))))
    
    (ok true)))

;; Process marketplace trade with royalties (FIXED VERSION)
(define-public (marketplace-trade
                (item-id uint)
                (trade-amount uint))
  (let ((item (unwrap! (map-get? game-items { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST))
        (current-owner (get current-owner item))
        (royalty-payment (/ (* trade-amount (get creator-royalty item)) LOOT-BASIS))
        (seller-payment (- trade-amount royalty-payment)))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (get tradeable item) ERR-PARAMETER-ERROR)
    (asserts! (get minted item) ERR-PARAMETER-ERROR)
    (asserts! (> trade-amount u0) ERR-PARAMETER-ERROR)
    (asserts! (>= (stx-get-balance tx-sender) trade-amount) ERR-WALLET-INSUFFICIENT)
    ;; Validate that tx-sender is not the current owner (can't buy from yourself)
    (asserts! (not (is-eq tx-sender current-owner)) ERR-INVALID-OWNER)
    
    ;; Transfer trade amount to contract
    (try! (stx-transfer? trade-amount tx-sender (as-contract tx-sender)))
    
    ;; Pay current owner (now using validated owner from contract state)
    (if (> seller-payment u0)
        (as-contract (try! (stx-transfer? seller-payment tx-sender current-owner)))
        true)
    
    ;; Update current owner
    (map-set game-items
      { item-id: item-id }
      (merge item { current-owner: tx-sender }))
    
    ;; Distribute royalties to developers
    (try! (distribute-loot-royalties item-id royalty-payment))
    
    (ok true)))

;; Alternative marketplace trade with explicit ownership verification
(define-public (marketplace-trade-verified
                (item-id uint)
                (previous-owner principal)
                (trade-amount uint))
  (let ((item (unwrap! (map-get? game-items { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST))
        (stored-owner (get current-owner item))
        (royalty-payment (/ (* trade-amount (get creator-royalty item)) LOOT-BASIS))
        (seller-payment (- trade-amount royalty-payment)))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (get tradeable item) ERR-PARAMETER-ERROR)
    (asserts! (get minted item) ERR-PARAMETER-ERROR)
    (asserts! (> trade-amount u0) ERR-PARAMETER-ERROR)
    (asserts! (>= (stx-get-balance tx-sender) trade-amount) ERR-WALLET-INSUFFICIENT)
    ;; SECURITY FIX: Validate that provided previous-owner matches stored owner
    (asserts! (is-eq previous-owner stored-owner) ERR-INVALID-OWNER)
    ;; Validate that tx-sender is not the current owner
    (asserts! (not (is-eq tx-sender stored-owner)) ERR-INVALID-OWNER)
    
    ;; Transfer trade amount to contract
    (try! (stx-transfer? trade-amount tx-sender (as-contract tx-sender)))
    
    ;; Pay verified owner
    (if (> seller-payment u0)
        (as-contract (try! (stx-transfer? seller-payment tx-sender previous-owner)))
        true)
    
    ;; Update current owner
    (map-set game-items
      { item-id: item-id }
      (merge item { current-owner: tx-sender }))
    
    ;; Distribute royalties to developers
    (try! (distribute-loot-royalties item-id royalty-payment))
    
    (ok true)))

;; Distribute loot royalties to developers
(define-private (distribute-loot-royalties (item-id uint) (total-royalties uint))
  (let ((developer-list (get developers (unwrap! (map-get? item-developers { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST))))
    (begin
      (fold distribute-to-developer developer-list { item-id: item-id, total-royalties: total-royalties, success: true })
      (ok true))))

;; Helper function to distribute royalties to individual developer
(define-private (distribute-to-developer 
                (developer principal) 
                (data { item-id: uint, total-royalties: uint, success: bool }))
  (if (get success data)
      (let ((developer-data (map-get? developers { item-id: (get item-id data), developer: developer })))
        (if (is-some developer-data)
            (let ((dev-share (get creation-share (unwrap-panic developer-data)))
                  (dev-royalty (/ (* (get total-royalties data) dev-share) LOOT-BASIS))
                  (current-rewards (default-to { reward-balance: u0 }
                                   (map-get? loot-rewards { item-id: (get item-id data), developer: developer }))))
              
              ;; Add to loot rewards
              (map-set loot-rewards
                { item-id: (get item-id data), developer: developer }
                { reward-balance: (+ (get reward-balance current-rewards) dev-royalty) })
              
              data)
            data))
      data))

;; Claim accumulated loot rewards
(define-public (claim-loot-rewards (item-id uint))
  (let ((rewards (unwrap! (map-get? loot-rewards { item-id: item-id, developer: tx-sender }) ERR-NO-LOOT-REWARDS))
        (amount (get reward-balance rewards)))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (> amount u0) ERR-NO-LOOT-REWARDS)
    
    ;; Reset reward balance
    (map-set loot-rewards
      { item-id: item-id, developer: tx-sender }
      { reward-balance: u0 })
    
    ;; Transfer rewards
    (as-contract (try! (stx-transfer? amount tx-sender tx-sender)))
    
    (ok amount)))

;; Transfer item ownership (owner-initiated)
(define-public (transfer-ownership (item-id uint) (new-owner principal))
  (let ((item (unwrap! (map-get? game-items { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST)))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (get minted item) ERR-PARAMETER-ERROR)
    (asserts! (get tradeable item) ERR-PARAMETER-ERROR)
    (asserts! (is-eq tx-sender (get current-owner item)) ERR-UNAUTHORIZED-USER)
    (asserts! (not (is-eq tx-sender new-owner)) ERR-PARAMETER-ERROR)
    
    ;; Update owner
    (map-set game-items
      { item-id: item-id }
      (merge item { current-owner: new-owner }))
    
    (ok true)))

;; Toggle item tradeable status (lead designer only)
(define-public (toggle-tradeable-status (item-id uint))
  (let ((item (unwrap! (map-get? game-items { item-id: item-id }) ERR-ITEM-DOES-NOT-EXIST)))
    
    ;; Validate
    (asserts! (> item-id u0) ERR-PARAMETER-ERROR)
    (asserts! (is-eq tx-sender (get lead-designer item)) ERR-UNAUTHORIZED-USER)
    
    ;; Toggle tradeable status
    (map-set game-items
      { item-id: item-id }
      (merge item { tradeable: (not (get tradeable item)) }))
    
    (ok true)))

;; Read-only functions
(define-read-only (get-item (item-id uint))
  (map-get? game-items { item-id: item-id }))

(define-read-only (get-developer (item-id uint) (developer principal))
  (map-get? developers { item-id: item-id, developer: developer }))

(define-read-only (get-loot-rewards (item-id uint) (developer principal))
  (default-to { reward-balance: u0 }
              (map-get? loot-rewards { item-id: item-id, developer: developer })))

(define-read-only (get-item-developers (item-id uint))
  (map-get? item-developers { item-id: item-id }))

(define-read-only (get-next-item-id)
  (var-get next-item-id))

(define-read-only (item-exists (item-id uint))
  (is-some (map-get? game-items { item-id: item-id })))

(define-read-only (get-total-items)
  (- (var-get next-item-id) u1))

(define-read-only (get-current-owner (item-id uint))
  (match (map-get? game-items { item-id: item-id })
    item (some (get current-owner item))
    none))