;; Temporal Carbon Protocol (TCP)
;; Decentralized Time-Locked Carbon Sequestration Futures Market

;; Constants
(define-constant PROTOCOL-STEWARD tx-sender)
(define-constant ERR-STEWARD-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-SEQUESTRATION-EXPIRED (err u104))
(define-constant ERR-HARVEST-ALREADY-PROCESSED (err u105))
(define-constant ERR-MATURITY-NOT-REACHED (err u106))
(define-constant ERR-VALIDATOR-NOT-AUTHORIZED (err u107))
(define-constant ERR-INVALID-PARAMETERS (err u108))

;; Data Variables
(define-data-var primary-carbon-validator principal PROTOCOL-STEWARD)
(define-data-var temporal-staking-rate uint u150) ;; 1.5% temporal premium in basis points
(define-data-var total-futures-created uint u0)
(define-data-var protocol-carbon-vault uint u0)

;; Valid sequestration methods - Fixed string length to match longest string
(define-constant VALID-SEQUESTRATION-METHODS (list "biochar" "forestry" "ocean-algae" "soil-carbon"))

;; Validation helper - Fixed parameter type to match list elements (soil-carbon = 11 chars)
(define-private (is-sequestration-method-valid (method-type (string-ascii 11)))
  (is-some (index-of VALID-SEQUESTRATION-METHODS method-type))
)

;; Valid principals check
(define-private (is-valid-principal (addr principal))
  (not (is-eq addr 'SP000000000000000000002Q6VF78))
)

;; Carbon Future Structure
(define-map temporal-carbon-futures
  { future-id: uint }
  {
    carbon-farmer: principal,
    temporal-stake: uint,
    sequestration-commitment: uint,
    atmospheric-baseline: uint,
    temporal-lock-duration: uint,
    plantation-block: uint,
    maturity-block: uint,
    harvest-processed: bool,
    future-active: bool
  }
)

;; Carbon Measurement Registry - Updated to use consistent string length
(define-map carbon-measurement-registry
  { method-type: (string-ascii 11), measurement-block: uint }
  {
    co2-captured: uint,
    atmospheric-verification: (buff 32),
    measurement-timestamp: uint,
    carbon-validator: principal
  }
)

;; Authorized Carbon Validators
(define-map authorized-carbon-validators
  { validator: principal }
  { is-authorized: bool, validator-specialty: (string-ascii 20) }
)

;; Carbon Farmer Profiles
(define-map carbon-farmer-profiles
  { carbon-farmer: principal }
  {
    total-futures: uint,
    total-harvests: uint,
    total-co2-sequestered: uint,
    temporal-reliability-score: uint
  }
)

;; Temporal Events - Updated to use consistent string length
(define-map temporal-carbon-events
  { future-id: uint, event-type: (string-ascii 25) }
  {
    event-block: uint,
    timestamp: uint,
    carbon-data: uint
  }
)

;; Read-only functions

(define-read-only (get-temporal-carbon-future (future-id uint))
  (map-get? temporal-carbon-futures { future-id: future-id })
)

(define-read-only (get-carbon-measurement (method-type (string-ascii 11)) (measurement-block uint))
  (map-get? carbon-measurement-registry { method-type: method-type, measurement-block: measurement-block })
)

(define-read-only (get-carbon-farmer-profile (carbon-farmer principal))
  (default-to 
    { total-futures: u0, total-harvests: u0, total-co2-sequestered: u0, temporal-reliability-score: u0 }
    (map-get? carbon-farmer-profiles { carbon-farmer: carbon-farmer })
  )
)

(define-read-only (is-carbon-validator-authorized (validator principal))
  (default-to false (get is-authorized (map-get? authorized-carbon-validators { validator: validator })))
)

(define-read-only (calculate-temporal-premium (sequestration-commitment uint) (lock-duration uint))
  (let ((base-premium (/ (* sequestration-commitment u200) u10000))) ;; 2% base rate
    (/ (* base-premium lock-duration) u52560000) ;; Adjust for temporal lock (blocks per year)
  )
)

(define-read-only (get-protocol-carbon-metrics)
  {
    total-futures: (var-get total-futures-created),
    carbon-vault: (var-get protocol-carbon-vault),
    primary-validator: (var-get primary-carbon-validator),
    temporal-rate: (var-get temporal-staking-rate)
  }
)

;; Administrative functions

(define-public (set-primary-carbon-validator (new-validator principal))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL-STEWARD) ERR-STEWARD-ONLY)
    (asserts! (is-valid-principal new-validator) ERR-INVALID-PARAMETERS)
    (var-set primary-carbon-validator new-validator)
    (ok true)
  )
)

(define-public (authorize-carbon-validator (validator-addr principal) (specialty (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL-STEWARD) ERR-STEWARD-ONLY)
    (asserts! (is-valid-principal validator-addr) ERR-INVALID-PARAMETERS)
    (map-set authorized-carbon-validators 
      { validator: validator-addr } 
      { is-authorized: true, validator-specialty: specialty }
    )
    (ok true)
  )
)

(define-public (revoke-carbon-validator (validator-addr principal))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL-STEWARD) ERR-STEWARD-ONLY)
    (asserts! (is-valid-principal validator-addr) ERR-INVALID-PARAMETERS)
    (map-set authorized-carbon-validators 
      { validator: validator-addr } 
      { is-authorized: false, validator-specialty: "revoked" }
    )
    (ok true)
  )
)

(define-public (update-temporal-staking-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL-STEWARD) ERR-STEWARD-ONLY)
    (asserts! (<= new-rate u1000) ERR-INVALID-PARAMETERS) ;; Max 10%
    (var-set temporal-staking-rate new-rate)
    (ok true)
  )
)

;; Carbon Validator functions - Updated parameter type

(define-public (submit-carbon-measurement 
  (method-type (string-ascii 11)) 
  (co2-captured uint)
  (atmospheric-verification (buff 32))
)
  (let ((current-block block-height))
    (asserts! (is-carbon-validator-authorized tx-sender) ERR-VALIDATOR-NOT-AUTHORIZED)
    (asserts! (is-sequestration-method-valid method-type) ERR-INVALID-PARAMETERS)
    (map-set carbon-measurement-registry 
      { method-type: method-type, measurement-block: current-block }
      { 
        co2-captured: co2-captured,
        atmospheric-verification: atmospheric-verification,
        measurement-timestamp: (unwrap-panic (get-block-info? time current-block)), 
        carbon-validator: tx-sender 
      }
    )
    (ok true)
  )
)

;; Core temporal carbon futures functions

(define-public (create-temporal-carbon-future 
  (sequestration-commitment uint)
  (atmospheric-baseline uint)
  (temporal-lock-duration uint)
  (sequestration-method (string-ascii 11))
)
  (let (
    (future-id (+ (var-get total-futures-created) u1))
    (temporal-premium (calculate-temporal-premium sequestration-commitment temporal-lock-duration))
    (total-stake temporal-premium)
    (current-block block-height)
    (maturity-block (+ current-block temporal-lock-duration))
    (current-profile (get-carbon-farmer-profile tx-sender))
  )
    (asserts! (> sequestration-commitment u0) ERR-INVALID-PARAMETERS)
    (asserts! (> atmospheric-baseline u0) ERR-INVALID-PARAMETERS)
    (asserts! (> temporal-lock-duration u0) ERR-INVALID-PARAMETERS)
    (asserts! (is-sequestration-method-valid sequestration-method) ERR-INVALID-PARAMETERS)
    (asserts! (>= (stx-get-balance tx-sender) total-stake) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer temporal stake
    (try! (stx-transfer? total-stake tx-sender (as-contract tx-sender)))
    
    ;; Create temporal carbon future
    (map-set temporal-carbon-futures 
      { future-id: future-id }
      {
        carbon-farmer: tx-sender,
        temporal-stake: temporal-premium,
        sequestration-commitment: sequestration-commitment,
        atmospheric-baseline: atmospheric-baseline,
        temporal-lock-duration: temporal-lock-duration,
        plantation-block: current-block,
        maturity-block: maturity-block,
        harvest-processed: false,
        future-active: true
      }
    )
    
    ;; Update farmer profile
    (map-set carbon-farmer-profiles 
      { carbon-farmer: tx-sender }
      {
        total-futures: (+ (get total-futures current-profile) u1),
        total-harvests: (get total-harvests current-profile),
        total-co2-sequestered: (get total-co2-sequestered current-profile),
        temporal-reliability-score: (get temporal-reliability-score current-profile)
      }
    )
    
    ;; Update protocol state
    (var-set total-futures-created future-id)
    (var-set protocol-carbon-vault (+ (var-get protocol-carbon-vault) temporal-premium))
    
    (ok future-id)
  )
)

(define-public (harvest-temporal-carbon-future (future-id uint))
  (let (
    (future (unwrap! (get-temporal-carbon-future future-id) ERR-NOT-FOUND))
    (current-block block-height)
    (biochar-measurement (get-carbon-measurement "biochar" current-block))
    (forestry-measurement (get-carbon-measurement "forestry" current-block))
    (current-profile (get-carbon-farmer-profile (get carbon-farmer future)))
  )
    (asserts! (is-eq tx-sender (get carbon-farmer future)) ERR-STEWARD-ONLY)
    (asserts! (get future-active future) ERR-NOT-FOUND)
    (asserts! (not (get harvest-processed future)) ERR-HARVEST-ALREADY-PROCESSED)
    (asserts! (>= current-block (get maturity-block future)) ERR-MATURITY-NOT-REACHED)
    
    ;; Check if sequestration commitment was met
    (let (
      (biochar-sequestered 
        (match biochar-measurement
          measurement-entry (get co2-captured measurement-entry)
          u0
        )
      )
      (forestry-sequestered 
        (match forestry-measurement
          measurement-entry (get co2-captured measurement-entry)
          u0
        )
      )
      (total-sequestered (+ biochar-sequestered forestry-sequestered))
    )
      (asserts! (>= total-sequestered (get sequestration-commitment future)) ERR-MATURITY-NOT-REACHED)
      
      ;; Calculate carbon rewards based on over-performance
      (let (
        (base-reward (get temporal-stake future))
        (performance-multiplier (/ total-sequestered (get sequestration-commitment future)))
        (temporal-bonus (/ (* base-reward performance-multiplier) u100))
        (total-reward (+ base-reward temporal-bonus))
      )
        ;; Transfer rewards
        (try! (as-contract (stx-transfer? total-reward tx-sender (get carbon-farmer future))))
        
        ;; Update future
        (map-set temporal-carbon-futures 
          { future-id: future-id }
          (merge future { harvest-processed: true, future-active: false })
        )
        
        ;; Update farmer profile
        (map-set carbon-farmer-profiles 
          { carbon-farmer: (get carbon-farmer future) }
          (merge current-profile { 
            total-harvests: (+ (get total-harvests current-profile) u1),
            total-co2-sequestered: (+ (get total-co2-sequestered current-profile) total-sequestered),
            temporal-reliability-score: (+ (get temporal-reliability-score current-profile) u10)
          })
        )
        
        ;; Record temporal event
        (map-set temporal-carbon-events
          { future-id: future-id, event-type: "harvest-completed" }
          { 
            event-block: current-block, 
            timestamp: (unwrap-panic (get-block-info? time current-block)), 
            carbon-data: total-sequestered 
          }
        )
        
        (ok total-reward)
      )
    )
  )
)

(define-public (abandon-temporal-future (future-id uint))
  (let (
    (future (unwrap! (get-temporal-carbon-future future-id) ERR-NOT-FOUND))
    (current-block block-height)
  )
    (asserts! (is-eq tx-sender (get carbon-farmer future)) ERR-STEWARD-ONLY)
    (asserts! (get future-active future) ERR-NOT-FOUND)
    (asserts! (not (get harvest-processed future)) ERR-HARVEST-ALREADY-PROCESSED)
    (asserts! (< current-block (+ (get plantation-block future) u52560)) ERR-SEQUESTRATION-EXPIRED) ;; Allow abandonment within ~365 days
    
    ;; Partial stake refund for early abandonment (50% penalty)
    (let ((refund-amount (/ (get temporal-stake future) u2)))
      (try! (as-contract (stx-transfer? refund-amount tx-sender (get carbon-farmer future))))
      
      ;; Deactivate future
      (map-set temporal-carbon-futures 
        { future-id: future-id }
        (merge future { future-active: false })
      )
      
      (ok refund-amount)
    )
  )
)

;; Temporal arbitrage functions

(define-public (create-carbon-forward-contract 
  (future-id uint) 
  (forward-price uint) 
  (buyer principal)
)
  (let ((future (unwrap! (get-temporal-carbon-future future-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get carbon-farmer future)) ERR-STEWARD-ONLY)
    (asserts! (get future-active future) ERR-NOT-FOUND)
    (asserts! (is-valid-principal buyer) ERR-INVALID-PARAMETERS)
    
    ;; Create forward contract (simplified implementation)
    ;; In practice, this would create a separate forward contract structure
    (ok true)
  )
)

;; Vault management

(define-public (withdraw-protocol-carbon-vault (amount uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL-STEWARD) ERR-STEWARD-ONLY)
    (asserts! (<= amount (var-get protocol-carbon-vault)) ERR-INSUFFICIENT-BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender PROTOCOL-STEWARD)))
    (var-set protocol-carbon-vault (- (var-get protocol-carbon-vault) amount))
    (ok amount)
  )
)

;; Carbon credit trading functions

(define-public (update-reliability-score (carbon-farmer principal) (score-adjustment uint))
  (let ((current-profile (get-carbon-farmer-profile carbon-farmer)))
    (asserts! (is-carbon-validator-authorized tx-sender) ERR-VALIDATOR-NOT-AUTHORIZED)
    (map-set carbon-farmer-profiles
      { carbon-farmer: carbon-farmer }
      (merge current-profile { 
        temporal-reliability-score: (+ (get temporal-reliability-score current-profile) score-adjustment) 
      })
    )
    (ok true)
  )
)

;; Initialize contract
(begin
  (map-set authorized-carbon-validators 
    { validator: PROTOCOL-STEWARD } 
    { is-authorized: true, validator-specialty: "protocol-admin" }
  )
)