;; GridFlow Energy Network - Core Contract
;; This contract manages the central functionality of the GridFlow Energy Network,
;; a decentralized platform for peer-to-peer energy trading and distribution.
;; It facilitates user registration, energy listings, transaction processing,
;; and settlement between energy producers and consumers.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-USER-ALREADY-EXISTS (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-INVALID-ROLE (err u103))
(define-constant ERR-LISTING-NOT-FOUND (err u104))
(define-constant ERR-INSUFFICIENT-ENERGY (err u105))
(define-constant ERR-TRANSACTION-FAILED (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-LISTING-NOT-ACTIVE (err u108))
(define-constant ERR-SELF-TRANSACTION (err u109))
(define-constant ERR-REPUTATION-NOT-FOUND (err u110))
(define-constant ERR-UNAUTHORIZED-SETTLEMENT (err u111))

;; User role constants
(define-constant ROLE-PRODUCER u1)
(define-constant ROLE-CONSUMER u2)
(define-constant ROLE-BOTH u3)

;; Status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-INACTIVE u2)

;; Data maps and variables

;; Store user profiles with their roles and information
(define-map users
  { user: principal }
  {
    role: uint,                  ;; 1=producer, 2=consumer, 3=both
    location: (string-ascii 50), ;; Grid location identifier
    registration-time: uint,     ;; When they registered
    status: uint                 ;; 1=active, 2=inactive
  }
)

;; Store energy listings by producers
(define-map energy-listings
  { listing-id: uint }
  {
    producer: principal,
    energy-amount: uint,         ;; Amount in kWh * 100 (for 2 decimal places)
    price-per-unit: uint,        ;; Price in microstacks per kWh
    available-amount: uint,      ;; Remaining energy available
    creation-time: uint,
    expiration-time: uint,
    status: uint                 ;; 1=active, 2=inactive, 3=fulfilled
  }
)

;; Store transactions between producers and consumers
(define-map energy-transactions
  { transaction-id: uint }
  {
    producer: principal,
    consumer: principal,
    listing-id: uint,
    energy-amount: uint,         ;; Amount in kWh * 100
    total-price: uint,           ;; In microstacks
    transaction-time: uint,
    status: uint,                ;; 1=pending, 2=completed, 3=cancelled
    settlement-id: (optional uint)
  }
)

;; Store energy settlements based on smart meter readings
(define-map energy-settlements
  { settlement-id: uint }
  {
    transaction-id: uint,
    actual-energy-delivered: uint, ;; Actual energy in kWh * 100
    settlement-amount: uint,       ;; Final payment in microstacks
    settlement-time: uint,
    verified-by: principal        ;; Oracle or authorized smart meter
  }
)

;; Track user reputation based on successful transactions
(define-map user-reputation
  { user: principal }
  {
    completed-transactions: uint,
    positive-ratings: uint,
    total-energy-traded: uint,    ;; In kWh * 100
    reputation-score: uint        ;; Score out of 100
  }
)

;; Contract state counters
(define-data-var next-listing-id uint u1)
(define-data-var next-transaction-id uint u1)
(define-data-var next-settlement-id uint u1)
(define-data-var total-users uint u0)
(define-data-var total-energy-traded uint u0)  ;; In kWh * 100
(define-data-var contract-owner principal tx-sender)

;; Private functions

;; Check if user exists
(define-private (is-user-registered (user principal))
  (is-some (map-get? users { user: user }))
)

;; Check if user has specific role
(define-private (has-role (user principal) (required-role uint))
  (let ((user-info (unwrap! (map-get? users { user: user }) false)))
    (or
      (is-eq (get role user-info) required-role)
      (is-eq (get role user-info) ROLE-BOTH)
    )
  )
)

;; Check if caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Calculate reputation score based on ratings and transactions
(define-private (calculate-reputation (positive uint) (total uint))
  (if (is-eq total u0)
    u0 ;; No transactions yet
    (/ (* positive u100) total) ;; Score as percentage
  )
)

;; Update user reputation after a successful transaction
(define-private (update-reputation (user principal) (positive bool) (energy-amount uint))
  (let (
    (current-reputation (default-to 
      {
        completed-transactions: u0,
        positive-ratings: u0,
        total-energy-traded: u0,
        reputation-score: u0
      }
      (map-get? user-reputation { user: user })
    ))
  )
    (map-set user-reputation 
      { user: user }
      {
        completed-transactions: (+ (get completed-transactions current-reputation) u1),
        positive-ratings: (+ (get positive-ratings current-reputation) (if positive u1 u0)),
        total-energy-traded: (+ (get total-energy-traded current-reputation) energy-amount),
        reputation-score: (calculate-reputation 
          (+ (get positive-ratings current-reputation) (if positive u1 u0))
          (+ (get completed-transactions current-reputation) u1)
        )
      }
    )
  )
)

;; Read-only functions

;; Get user profile information
(define-read-only (get-user-info (user principal))
  (map-get? users { user: user })
)

;; Get energy listing details
(define-read-only (get-energy-listing (listing-id uint))
  (map-get? energy-listings { listing-id: listing-id })
)

;; Get transaction details
(define-read-only (get-transaction (transaction-id uint))
  (map-get? energy-transactions { transaction-id: transaction-id })
)

;; Get settlement details
(define-read-only (get-settlement (settlement-id uint))
  (map-get? energy-settlements { settlement-id: settlement-id })
)

;; Get reputation of a user
(define-read-only (get-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Check if a user is a producer
(define-read-only (is-producer (user principal))
  (match (map-get? users { user: user })
    user-data (or (is-eq (get role user-data) ROLE-PRODUCER) 
                 (is-eq (get role user-data) ROLE-BOTH))
    false
  )
)

;; Check if a user is a consumer
(define-read-only (is-consumer (user principal))
  (match (map-get? users { user: user })
    user-data (or (is-eq (get role user-data) ROLE-CONSUMER) 
                 (is-eq (get role user-data) ROLE-BOTH))
    false
  )
)

;; Calculate reputation score for display
(define-read-only (get-reputation-score (user principal))
  (match (map-get? user-reputation { user: user })
    reputation (get reputation-score reputation)
    u0
  )
)

;; Get total platform statistics
(define-read-only (get-platform-stats)
  {
    total-users: (var-get total-users),
    total-energy-traded: (var-get total-energy-traded)
  }
)

;; Public functions

;; Register a new user
(define-public (register-user (role uint) (location (string-ascii 50)))
  (begin
    ;; Validate role value
    (asserts! (or (is-eq role ROLE-PRODUCER) (is-eq role ROLE-CONSUMER) (is-eq role ROLE-BOTH)) ERR-INVALID-ROLE)
    
    ;; Check if user already exists
    (asserts! (not (is-user-registered tx-sender)) ERR-USER-ALREADY-EXISTS)
    
    ;; Register the user
    (map-set users
      { user: tx-sender }
      {
        role: role,
        location: location,
        registration-time: block-height,
        status: STATUS-ACTIVE
      }
    )
    
    ;; Initialize user reputation
    (map-set user-reputation
      { user: tx-sender }
      {
        completed-transactions: u0,
        positive-ratings: u0,
        total-energy-traded: u0,
        reputation-score: u0
      }
    )
    
    ;; Increment total user count
    (var-set total-users (+ (var-get total-users) u1))
    
    (ok true)
  )
)

;; Update user profile
(define-public (update-user-profile (role uint) (location (string-ascii 50)))
  (let ((user-data (unwrap! (map-get? users { user: tx-sender }) ERR-USER-NOT-FOUND)))
    ;; Validate role value
    (asserts! (or (is-eq role ROLE-PRODUCER) (is-eq role ROLE-CONSUMER) (is-eq role ROLE-BOTH)) ERR-INVALID-ROLE)
    
    ;; Update the user profile
    (map-set users
      { user: tx-sender }
      {
        role: role,
        location: location,
        registration-time: (get registration-time user-data),
        status: (get status user-data)
      }
    )
    
    (ok true)
  )
)

;; Create a new energy listing (for producers)
(define-public (create-energy-listing (energy-amount uint) (price-per-unit uint) (expiration-time uint))
  (begin
    ;; Ensure user is registered as a producer
    (asserts! (is-producer tx-sender) ERR-UNAUTHORIZED)
    
    ;; Validate inputs
    (asserts! (> energy-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-unit u0) ERR-INVALID-AMOUNT)
    (asserts! (> expiration-time block-height) ERR-INVALID-AMOUNT)
    
    ;; Create the listing
    (let ((listing-id (var-get next-listing-id)))
      (map-set energy-listings
        { listing-id: listing-id }
        {
          producer: tx-sender,
          energy-amount: energy-amount,
          price-per-unit: price-per-unit,
          available-amount: energy-amount,
          creation-time: block-height,
          expiration-time: expiration-time,
          status: STATUS-ACTIVE
        }
      )
      
      ;; Increment listing ID
      (var-set next-listing-id (+ listing-id u1))
      
      (ok listing-id)
    )
  )
)

;; Update an energy listing
(define-public (update-energy-listing (listing-id uint) (price-per-unit uint) (expiration-time uint) (status uint))
  (let ((listing (unwrap! (map-get? energy-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND)))
    ;; Ensure caller is the producer who created the listing
    (asserts! (is-eq tx-sender (get producer listing)) ERR-NOT-AUTHORIZED)
    
    ;; Validate inputs
    (asserts! (> price-per-unit u0) ERR-INVALID-AMOUNT)
    (asserts! (> expiration-time block-height) ERR-INVALID-AMOUNT)
    
    ;; Update the listing
    (map-set energy-listings
      { listing-id: listing-id }
      {
        producer: (get producer listing),
        energy-amount: (get energy-amount listing),
        price-per-unit: price-per-unit,
        available-amount: (get available-amount listing),
        creation-time: (get creation-time listing),
        expiration-time: expiration-time,
        status: status
      }
    )
    
    (ok true)
  )
)

;; Buy energy from a listing
(define-public (buy-energy (listing-id uint) (energy-amount uint))
  (let (
    (listing (unwrap! (map-get? energy-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
    (total-price (* energy-amount (get price-per-unit listing)))
  )
    ;; Check that the listing is active
    (asserts! (is-eq (get status listing) STATUS-ACTIVE) ERR-LISTING-NOT-ACTIVE)
    
    ;; Check that the caller is a consumer
    (asserts! (is-consumer tx-sender) ERR-UNAUTHORIZED)
    
    ;; Check that the caller is not buying from themselves
    (asserts! (not (is-eq tx-sender (get producer listing))) ERR-SELF-TRANSACTION)
    
    ;; Check that there's enough energy available
    (asserts! (<= energy-amount (get available-amount listing)) ERR-INSUFFICIENT-ENERGY)
    
    ;; Check that the listing hasn't expired
    (asserts! (< block-height (get expiration-time listing)) ERR-LISTING-NOT-ACTIVE)
    
    ;; Process the payment
    (try! (stx-transfer? total-price tx-sender (get producer listing)))
    
    ;; Create the transaction record
    (let ((transaction-id (var-get next-transaction-id)))
      ;; Update the listing's available amount
      (map-set energy-listings
        { listing-id: listing-id }
        {
          producer: (get producer listing),
          energy-amount: (get energy-amount listing),
          price-per-unit: (get price-per-unit listing),
          available-amount: (- (get available-amount listing) energy-amount),
          creation-time: (get creation-time listing),
          expiration-time: (get expiration-time listing),
          status: (if (is-eq (- (get available-amount listing) energy-amount) u0) u2 u1) ;; Set to inactive if sold out
        }
      )
      
      ;; Record the transaction
      (map-set energy-transactions
        { transaction-id: transaction-id }
        {
          producer: (get producer listing),
          consumer: tx-sender,
          listing-id: listing-id,
          energy-amount: energy-amount,
          total-price: total-price,
          transaction-time: block-height,
          status: u1, ;; Pending
          settlement-id: none
        }
      )
      
      ;; Increment transaction ID
      (var-set next-transaction-id (+ transaction-id u1))
      
      ;; Update platform stats
      (var-set total-energy-traded (+ (var-get total-energy-traded) energy-amount))
      
      (ok transaction-id)
    )
  )
)

;; Settle a transaction (called by authorized smart meter or oracle)
(define-public (settle-transaction (transaction-id uint) (actual-energy-delivered uint))
  (let (
    (transaction (unwrap! (map-get? energy-transactions { transaction-id: transaction-id }) ERR-TRANSACTION-FAILED))
    (listing (unwrap! (map-get? energy-listings { listing-id: (get listing-id transaction) }) ERR-LISTING-NOT-FOUND))
  )
    ;; For now, simplified authorization - in production would be limited to oracle or smart meter contracts
    ;; This is a simplified implementation for the prototype
    (asserts! (or (is-contract-owner) (is-eq tx-sender (get producer transaction))) ERR-UNAUTHORIZED-SETTLEMENT)
    
    ;; Ensure transaction is pending
    (asserts! (is-eq (get status transaction) u1) ERR-TRANSACTION-FAILED)
    
    ;; Calculate final settlement amount based on actual energy delivered
    (let (
      (settlement-id (var-get next-settlement-id))
      (expected-energy (get energy-amount transaction))
      (price-per-unit (get price-per-unit listing))
      (settlement-amount (* actual-energy-delivered price-per-unit))
    )
      ;; Create settlement record
      (map-set energy-settlements
        { settlement-id: settlement-id }
        {
          transaction-id: transaction-id,
          actual-energy-delivered: actual-energy-delivered,
          settlement-amount: settlement-amount,
          settlement-time: block-height,
          verified-by: tx-sender
        }
      )
      
      ;; Update transaction as completed and link to settlement
      (map-set energy-transactions
        { transaction-id: transaction-id }
        {
          producer: (get producer transaction),
          consumer: (get consumer transaction),
          listing-id: (get listing-id transaction),
          energy-amount: (get energy-amount transaction),
          total-price: (get total-price transaction),
          transaction-time: (get transaction-time transaction),
          status: u2, ;; Completed
          settlement-id: (some settlement-id)
        }
      )
      
      ;; Update reputation for both parties (simplified for prototype)
      (update-reputation (get producer transaction) true actual-energy-delivered)
      (update-reputation (get consumer transaction) true actual-energy-delivered)
      
      ;; Increment settlement ID
      (var-set next-settlement-id (+ settlement-id u1))
      
      (ok settlement-id)
    )
  )
)

;; Submit rating for a completed transaction
(define-public (submit-rating (transaction-id uint) (is-positive bool))
  (let ((transaction (unwrap! (map-get? energy-transactions { transaction-id: transaction-id }) ERR-TRANSACTION-FAILED)))
    ;; Ensure transaction is completed
    (asserts! (is-eq (get status transaction) u2) ERR-TRANSACTION-FAILED)
    
    ;; Ensure caller was involved in the transaction
    (asserts! (or (is-eq tx-sender (get producer transaction)) 
                 (is-eq tx-sender (get consumer transaction))) 
             ERR-NOT-AUTHORIZED)
    
    ;; Determine which party to rate
    (let ((party-to-rate (if (is-eq tx-sender (get producer transaction))
                           (get consumer transaction)
                           (get producer transaction))))
      
      ;; Update reputation
      (update-reputation party-to-rate is-positive (get energy-amount transaction))
      
      (ok true)
    )
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)