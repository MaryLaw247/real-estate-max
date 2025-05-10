;; Real Estate Property Management System
;; Stage 2: Enhanced lease management with property details and status tracking

;; System error definitions
(define-constant ACCESS-VIOLATION-CODE (err u301))
(define-constant ALREADY-REGISTERED-CODE (err u302))
(define-constant FUNDS-INSUFFICIENT-CODE (err u303))
(define-constant PROPERTY-NOT-FOUND-CODE (err u304))
(define-constant LEASE-PENDING-CODE (err u305))
(define-constant PROPERTY-AREA-LIMIT-CODE (err u306))
(define-constant COMMISSION-FEE-BOUNDS-CODE (err u307))
(define-constant LEASE-PERIOD-CODE (err u308))
(define-constant INVALID-PROPERTY-REFERENCE-CODE (err u309))
(define-constant DELISTED-STATUS-CODE (err u311))
(define-constant DEPOSIT-TOO-SMALL-CODE (err u312))
(define-constant ADDRESS-EMPTY-CODE (err u313))
(define-constant FEATURES-EMPTY-CODE (err u314))
(define-constant NETWORK-MAX-VALUE u2000000000)

;; Core data structures
(define-map property-registry
  { property-id: uint }
  {
    owner: principal,
    current-tenant: (optional principal),
    property-area: uint,
    owner-commission: uint,
    lease-period: uint,
    registration-timestamp: (optional uint),
    property-address: (string-ascii 30),
    property-features: (string-ascii 20),
    listing-status: (string-ascii 20)
  }
)

(define-map fund-repository principal uint)

(define-map owner-reputation-index principal uint)

(define-map owner-property-registry
  principal
  (list 10 uint)
)

;; Core business logic implementations
(define-public (register-property (property-area uint) (owner-commission uint) (lease-period uint) 
                             (property-address (string-ascii 30)) 
                             (property-features (string-ascii 20)))
  (let ((property-id (+ (var-get listing-sequence) u1)))
    ;; Input validation suite
    (asserts! (> property-area u0) PROPERTY-AREA-LIMIT-CODE)
    (asserts! (<= owner-commission u50) COMMISSION-FEE-BOUNDS-CODE)
    (asserts! (and (> lease-period u0) (<= lease-period u10000)) LEASE-PERIOD-CODE)
    ;; Address and features validation
    (asserts! (> (len property-address) u0) ADDRESS-EMPTY-CODE)
    (asserts! (> (len property-features) u0) FEATURES-EMPTY-CODE)
    
    ;; Register the new property
    (map-set property-registry 
      { property-id: property-id }
      {
        owner: tx-sender,
        current-tenant: none,
        property-area: property-area,
        owner-commission: owner-commission,
        lease-period: lease-period,
        registration-timestamp: none,
        property-address: property-address,
        property-features: property-features,
        listing-status: "AVAILABLE"
      }
    )
    
    ;; Update the owner's portfolio record
    (let 
      (
        (existing-portfolio (default-to (list) (map-get? owner-property-registry tx-sender)))
        (refreshed-portfolio (unwrap-panic (as-max-len? (concat (list property-id) existing-portfolio) u10)))
      )
      ;; Maintain at most 10 most recent properties
      (map-set owner-property-registry tx-sender refreshed-portfolio)
    )
    
    (var-set listing-sequence property-id)
    (ok property-id)
  )
)

(define-public (claim-lease-rights (property-id uint))
  (let (
    (property-details (unwrap! (map-get? property-registry { property-id: property-id }) PROPERTY-NOT-FOUND-CODE))
    (tenant-funds (default-to u0 (map-get? fund-repository tx-sender)))
  )
    ;; Validate transaction parameters
    (asserts! (<= property-id (var-get listing-sequence)) INVALID-PROPERTY-REFERENCE-CODE)
    (asserts! (is-none (get current-tenant property-details)) ALREADY-REGISTERED-CODE)
    (asserts! (is-eq (get listing-status property-details) "AVAILABLE") PROPERTY-NOT-FOUND-CODE)
    (asserts! (>= tenant-funds (get property-area property-details)) FUNDS-INSUFFICIENT-CODE)
    
    ;; Update property ownership records
    (map-set property-registry { property-id: property-id }
      (merge property-details { 
        current-tenant: (some tx-sender),
        registration-timestamp: (some block-height),
        listing-status: "RIGHTS_CLAIMED"
      })
    )
    
    ;; Execute financial transactions
    (map-set fund-repository tx-sender (- tenant-funds (get property-area property-details)))
    (map-set fund-repository (get owner property-details) 
      (+ (default-to u0 (map-get? fund-repository (get owner property-details))) 
         (get property-area property-details)))
    
    (ok true)
  )
)

(define-public (complete-lease (property-id uint))
  (let (
    (property-details (unwrap! (map-get? property-registry { property-id: property-id }) PROPERTY-NOT-FOUND-CODE))
    (tenant-balance (default-to u0 (map-get? fund-repository tx-sender)))
    (initial-cost (get property-area property-details))
    (owner-bonus (/ (* (get property-area property-details) (get owner-commission property-details)) u100))
    (total-payment (+ initial-cost owner-bonus))
  )
    ;; Comprehensive validation checks
    (asserts! (<= property-id (var-get listing-sequence)) INVALID-PROPERTY-REFERENCE-CODE)
    (asserts! (is-eq (get current-tenant property-details) (some tx-sender)) ACCESS-VIOLATION-CODE)
    (asserts! (is-eq (get listing-status property-details) "RIGHTS_CLAIMED") PROPERTY-NOT-FOUND-CODE)
    (asserts! (>= (- block-height (unwrap! (get registration-timestamp property-details) PROPERTY-NOT-FOUND-CODE)) 
                (get lease-period property-details)) LEASE-PENDING-CODE)
    (asserts! (>= tenant-balance total-payment) FUNDS-INSUFFICIENT-CODE)
    
    ;; Execute payment to owner
    (map-set fund-repository tx-sender (- tenant-balance total-payment))
    (map-set fund-repository (get owner property-details) 
      (+ (default-to u0 (map-get? fund-repository (get owner property-details))) 
         total-payment)
    )
    
    ;; Update owner's reputation score
    (let ((reputation-score (default-to u0 (map-get? owner-reputation-index 
                        (get owner property-details)))))
      (map-set owner-reputation-index
        (get owner property-details)
        (+ reputation-score u1)
      )
    )
    
    ;; Update property lifecycle status
    (map-set property-registry { property-id: property-id } 
      (merge property-details { listing-status: "LEASE_COMPLETE" }))
    (ok true)
  )
)

(define-public (delist-property (property-id uint))
  (let (
    (property-details (unwrap! (map-get? property-registry { property-id: property-id }) PROPERTY-NOT-FOUND-CODE))
  )
    ;; Security validations
    (asserts! (<= property-id (var-get listing-sequence)) INVALID-PROPERTY-REFERENCE-CODE)
    (asserts! (is-eq (get owner property-details) tx-sender) ACCESS-VIOLATION-CODE)
    (asserts! (is-eq (get listing-status property-details) "AVAILABLE") PROPERTY-NOT-FOUND-CODE)
    
    ;; Change listing status
    (map-set property-registry { property-id: property-id } 
      (merge property-details { listing-status: "DELISTED" }))
    (ok true)
  )
)

(define-public (deposit-funds (amount uint))
  (let (
    (existing-balance (default-to u0 (map-get? fund-repository tx-sender)))
  )
    ;; Input validation
    (asserts! (> amount u0) DEPOSIT-TOO-SMALL-CODE)
    (asserts! (<= amount NETWORK-MAX-VALUE) DEPOSIT-TOO-SMALL-CODE)
    (asserts! (<= (+ existing-balance amount) NETWORK-MAX-VALUE) DEPOSIT-TOO-SMALL-CODE)
    
    ;; Update account balance
    (map-set fund-repository tx-sender (+ existing-balance amount))
    (ok true)
  )
)

;; System query interfaces
(define-read-only (query-property-data (property-id uint))
  (map-get? property-registry { property-id: property-id })
)

(define-read-only (check-user-balance (entity principal))
  (default-to u0 (map-get? fund-repository entity))
)

(define-read-only (get-owner-reputation (owner principal))
  (default-to u0 (map-get? owner-reputation-index owner))
)

(define-read-only (list-owned-properties (entity principal))
  (default-to (list) (map-get? owner-property-registry entity))
)

;; Property value estimation
(define-read-only (estimate-property-value (property-id uint))
  (let (
    (property-details (default-to 
                        {
                          owner: tx-sender,
                          current-tenant: none,
                          property-area: u0,
                          owner-commission: u0,
                          lease-period: u0,
                          registration-timestamp: none,
                          property-address: "",
                          property-features: "",
                          listing-status: "NOT_FOUND"
                        }
                        (map-get? property-registry { property-id: property-id })))
  )
    (if (is-eq (get listing-status property-details) "NOT_FOUND")
        u0
        (let (
              (base-value (get property-area property-details))
              (owner-component (/ (* base-value (get owner-commission property-details)) u100))
             )
          (+ base-value owner-component)
        )
    )
  )
)

;; System initialization
(define-data-var listing-sequence uint u0)