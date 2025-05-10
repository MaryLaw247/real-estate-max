;; Real Estate Property Registry System
;; Stage 1: Fundamental property registration and querying

;; System error definitions
(define-constant ACCESS-VIOLATION-CODE (err u301))
(define-constant ALREADY-REGISTERED-CODE (err u302))
(define-constant FUNDS-INSUFFICIENT-CODE (err u303))
(define-constant PROPERTY-NOT-FOUND-CODE (err u304))
(define-constant PROPERTY-AREA-LIMIT-CODE (err u306))

;; Core data structures
(define-map property-registry
  { property-id: uint }
  {
    owner: principal,
    current-tenant: (optional principal),
    property-area: uint,
    registration-timestamp: (optional uint),
    property-address: (string-ascii 30)
  }
)

(define-map fund-repository principal uint)

(define-map owner-property-registry
  principal
  (list 10 uint)
)

;; Core business logic implementations
(define-public (register-property (property-area uint) (property-address (string-ascii 30)))
  (let ((property-id (+ (var-get listing-sequence) u1)))
    ;; Input validation
    (asserts! (> property-area u0) PROPERTY-AREA-LIMIT-CODE)
    (asserts! (> (len property-address) u0) (err u313))
    
    ;; Register the new property
    (map-set property-registry 
      { property-id: property-id }
      {
        owner: tx-sender,
        current-tenant: none,
        property-area: property-area,
        registration-timestamp: none,
        property-address: property-address
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
    (asserts! (is-none (get current-tenant property-details)) ALREADY-REGISTERED-CODE)
    (asserts! (>= tenant-funds (get property-area property-details)) FUNDS-INSUFFICIENT-CODE)
    
    ;; Update property ownership records
    (map-set property-registry { property-id: property-id }
      (merge property-details { 
        current-tenant: (some tx-sender),
        registration-timestamp: (some block-height)
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

(define-public (deposit-funds (amount uint))
  (let (
    (existing-balance (default-to u0 (map-get? fund-repository tx-sender)))
  )
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

(define-read-only (list-owned-properties (entity principal))
  (default-to (list) (map-get? owner-property-registry entity))
)

;; System initialization
(define-data-var listing-sequence uint u0)