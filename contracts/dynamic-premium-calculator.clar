;; Dynamic Premium Calculator
;; Dynamic insurance premium calculation based on route risk, weather, and rider behavior
;; This contract calculates insurance premiums using real-time data and risk assessment

;; Constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-POLICY-NOT-FOUND (err u201))
(define-constant ERR-INVALID-PARAMETERS (err u202))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u203))
(define-constant ERR-POLICY-EXPIRED (err u204))
(define-constant ERR-POLICY-ALREADY-EXISTS (err u205))
(define-constant ERR-INVALID-DURATION (err u206))
(define-constant ERR-WEATHER-DATA-UNAVAILABLE (err u207))
(define-constant ERR-ROUTE-DATA-UNAVAILABLE (err u208))
(define-constant ERR-CALCULATION-FAILED (err u209))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant BASE-PREMIUM-RATE u1000) ;; Base rate in microSTX per hour
(define-constant MAX-PREMIUM-MULTIPLIER u500) ;; 5x maximum multiplier
(define-constant MIN-PREMIUM-MULTIPLIER u50) ;; 0.5x minimum multiplier
(define-constant POLICY-DURATION-LIMIT u168) ;; Maximum 168 hours (1 week)
(define-constant SAFETY-SCORE-THRESHOLD u70) ;; Minimum safety score for standard rates
(define-constant HIGH_RISK_MULTIPLIER u200) ;; 2x multiplier for high-risk conditions
(define-constant LOW_RISK_MULTIPLIER u80) ;; 0.8x multiplier for low-risk conditions

;; Data Variables
(define-data-var total-policies uint u0)
(define-data-var total-premiums-collected uint u0)
(define-data-var contract-active bool true)
(define-data-var base-coverage-amount uint u1000000) ;; 1 STX base coverage
(define-data-var weather-oracle-fee uint u100) ;; Fee for weather data
(define-data-var route-analysis-fee uint u50) ;; Fee for route analysis

;; Insurance Policy Data
(define-map insurance-policies
  { policy-id: (string-ascii 64) }
  {
    device-id: (string-ascii 64),
    policyholder: principal,
    premium-amount: uint,
    coverage-amount: uint,
    start-time: uint,
    end-time: uint,
    is-active: bool,
    trip-id: (optional (string-ascii 32)),
    base-rate: uint,
    risk-multiplier: uint,
    weather-factor: uint,
    route-factor: uint,
    safety-factor: uint
  }
)

;; Premium Calculation Factors
(define-map risk-factors
  { factor-type: (string-ascii 20) }
  {
    base-multiplier: uint,
    min-value: uint,
    max-value: uint,
    description: (string-ascii 100)
  }
)

;; Weather Risk Assessment
(define-map weather-conditions
  { location-hash: (string-ascii 64), timestamp: uint }
  {
    temperature: int, ;; celsius * 10
    precipitation: uint, ;; mm * 100
    wind-speed: uint, ;; km/h * 10
    visibility: uint, ;; meters
    risk-level: uint, ;; 0-100 scale
    condition-type: (string-ascii 20) ;; "clear", "rain", "snow", "fog"
  }
)

;; Route Risk Data
(define-map route-risk-assessment
  { route-hash: (string-ascii 64) }
  {
    distance: uint, ;; meters
    traffic-density: uint, ;; 0-100 scale
    road-quality: uint, ;; 0-100 scale
    accident-history: uint, ;; incidents per km
    bike-lane-coverage: uint, ;; percentage
    night-lighting: uint, ;; 0-100 scale
    risk-score: uint ;; 0-100 scale
  }
)

;; Premium Payment Records
(define-map premium-payments
  { policy-id: (string-ascii 64), payment-id: uint }
  {
    amount-paid: uint,
    payment-time: uint,
    payment-method: (string-ascii 20),
    transaction-id: (string-ascii 64)
  }
)

;; Claims Data
(define-map insurance-claims
  { claim-id: (string-ascii 64) }
  {
    policy-id: (string-ascii 64),
    claimant: principal,
    claim-amount: uint,
    claim-type: (string-ascii 30), ;; "theft", "damage", "liability"
    incident-time: uint,
    claim-status: (string-ascii 20), ;; "pending", "approved", "denied"
    evidence-hash: (optional (string-ascii 64)),
    processing-time: uint
  }
)

;; Policy Statistics
(define-map policy-stats
  { device-id: (string-ascii 64) }
  {
    total-policies: uint,
    total-premiums-paid: uint,
    claims-count: uint,
    claims-amount: uint,
    current-risk-level: uint
  }
)

;; Public Functions

;; Initialize risk factors
(define-public (initialize-risk-factors)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Weather risk factors
    (map-set risk-factors
      { factor-type: "weather" }
      {
        base-multiplier: u100,
        min-value: u50,
        max-value: u300,
        description: "Weather condition multiplier"
      }
    )
    
    ;; Route risk factors  
    (map-set risk-factors
      { factor-type: "route" }
      {
        base-multiplier: u100,
        min-value: u60,
        max-value: u250,
        description: "Route safety multiplier"
      }
    )
    
    ;; Safety score factors
    (map-set risk-factors
      { factor-type: "safety" }
      {
        base-multiplier: u100,
        min-value: u70,
        max-value: u150,
        description: "Rider safety score multiplier"
      }
    )
    
    (ok true)
  )
)

;; Calculate premium for a policy
(define-public (calculate-premium
  (device-id (string-ascii 64))
  (duration-hours uint)
  (route-hash (string-ascii 64))
  (weather-location (string-ascii 64))
  (safety-score uint)
)
  (let
    (
      (weather-data (get-weather-risk weather-location))
      (route-data (get-route-risk route-hash))
      (weather-multiplier (get-weather-multiplier weather-data))
      (route-multiplier (get-route-multiplier route-data))
      (safety-multiplier (get-safety-multiplier safety-score))
      (base-amount (* BASE-PREMIUM-RATE duration-hours))
      (risk-adjusted-amount (/ (* (* (* base-amount weather-multiplier) route-multiplier) safety-multiplier) (* u100 u100 u100)))
    )
    
    ;; Validate inputs
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (> duration-hours u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= duration-hours POLICY-DURATION-LIMIT) ERR-INVALID-DURATION)
    (asserts! (<= safety-score u100) ERR-INVALID-PARAMETERS)
    
    ;; Ensure premium is within acceptable bounds
    (let
      (
        (final-premium (if (> risk-adjusted-amount (* base-amount MAX-PREMIUM-MULTIPLIER))
                          (* base-amount MAX-PREMIUM-MULTIPLIER)
                          (if (< risk-adjusted-amount (* base-amount MIN-PREMIUM-MULTIPLIER))
                              (* base-amount MIN-PREMIUM-MULTIPLIER)
                              risk-adjusted-amount)))
      )
      (ok {
        premium-amount: final-premium,
        base-amount: base-amount,
        weather-factor: weather-multiplier,
        route-factor: route-multiplier,
        safety-factor: safety-multiplier,
        duration: duration-hours
      })
    )
  )
)

;; Create a new insurance policy
(define-public (create-policy
  (policy-id (string-ascii 64))
  (device-id (string-ascii 64))
  (duration-hours uint)
  (route-hash (string-ascii 64))
  (weather-location (string-ascii 64))
  (safety-score uint)
  (trip-id (optional (string-ascii 32)))
)
  (let
    (
      (premium-calc (unwrap! (calculate-premium device-id duration-hours route-hash weather-location safety-score) ERR-CALCULATION-FAILED))
      (premium-amount (get premium-amount premium-calc))
      (current-time stacks-block-height)
      (end-time (+ current-time (* duration-hours u3600))) ;; Convert hours to seconds
      (existing-policy (map-get? insurance-policies { policy-id: policy-id }))
    )
    
    ;; Validate policy creation
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-none existing-policy) ERR-POLICY-ALREADY-EXISTS)
    (asserts! (>= (stx-get-balance tx-sender) premium-amount) ERR-INSUFFICIENT-PAYMENT)
    
    ;; Transfer premium payment
    (try! (stx-transfer? premium-amount tx-sender (as-contract tx-sender)))
    
    ;; Create the policy
    (map-set insurance-policies
      { policy-id: policy-id }
      {
        device-id: device-id,
        policyholder: tx-sender,
        premium-amount: premium-amount,
        coverage-amount: (var-get base-coverage-amount),
        start-time: current-time,
        end-time: end-time,
        is-active: true,
        trip-id: trip-id,
        base-rate: BASE-PREMIUM-RATE,
        risk-multiplier: (/ (* (get weather-factor premium-calc) (get route-factor premium-calc)) u100),
        weather-factor: (get weather-factor premium-calc),
        route-factor: (get route-factor premium-calc),
        safety-factor: (get safety-factor premium-calc)
      }
    )
    
    ;; Update statistics
    (var-set total-policies (+ (var-get total-policies) u1))
    (var-set total-premiums-collected (+ (var-get total-premiums-collected) premium-amount))
    
    ;; Update device statistics
    (let
      (
        (current-stats (default-to 
          { total-policies: u0, total-premiums-paid: u0, claims-count: u0, claims-amount: u0, current-risk-level: u50 }
          (map-get? policy-stats { device-id: device-id })
        ))
      )
      (map-set policy-stats
        { device-id: device-id }
        (merge current-stats
          {
            total-policies: (+ (get total-policies current-stats) u1),
            total-premiums-paid: (+ (get total-premiums-paid current-stats) premium-amount)
          }
        )
      )
    )
    
    (ok policy-id)
  )
)

;; Update weather data
(define-public (update-weather-data
  (location-hash (string-ascii 64))
  (temperature int)
  (precipitation uint)
  (wind-speed uint)
  (visibility uint)
  (condition-type (string-ascii 20))
)
  (let
    (
      (current-time stacks-block-height)
      (risk-level (calculate-weather-risk temperature precipitation wind-speed visibility condition-type))
    )
    
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    
    (map-set weather-conditions
      { location-hash: location-hash, timestamp: current-time }
      {
        temperature: temperature,
        precipitation: precipitation,
        wind-speed: wind-speed,
        visibility: visibility,
        risk-level: risk-level,
        condition-type: condition-type
      }
    )
    
    (ok risk-level)
  )
)

;; Update route risk data
(define-public (update-route-risk
  (route-hash (string-ascii 64))
  (distance uint)
  (traffic-density uint)
  (road-quality uint)
  (accident-history uint)
  (bike-lane-coverage uint)
  (night-lighting uint)
)
  (let
    (
      (risk-score (calculate-route-risk traffic-density road-quality accident-history bike-lane-coverage night-lighting))
    )
    
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    
    (map-set route-risk-assessment
      { route-hash: route-hash }
      {
        distance: distance,
        traffic-density: traffic-density,
        road-quality: road-quality,
        accident-history: accident-history,
        bike-lane-coverage: bike-lane-coverage,
        night-lighting: night-lighting,
        risk-score: risk-score
      }
    )
    
    (ok risk-score)
  )
)

;; Cancel policy (partial refund based on time remaining)
(define-public (cancel-policy (policy-id (string-ascii 64)))
  (let
    (
      (policy-info (unwrap! (map-get? insurance-policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
      (current-time stacks-block-height)
    )
    
    (asserts! (is-eq tx-sender (get policyholder policy-info)) ERR-UNAUTHORIZED)
    (asserts! (get is-active policy-info) ERR-POLICY-EXPIRED)
    (asserts! (< current-time (get end-time policy-info)) ERR-POLICY-EXPIRED)
    
    ;; Calculate refund (70% of remaining time value)
    (let
      (
        (time-remaining (- (get end-time policy-info) current-time))
        (total-duration (- (get end-time policy-info) (get start-time policy-info)))
        (refund-amount (/ (* (* (get premium-amount policy-info) time-remaining) u70) (* total-duration u100)))
      )
      
      ;; Deactivate policy
      (map-set insurance-policies
        { policy-id: policy-id }
        (merge policy-info { is-active: false })
      )
      
      ;; Process refund
      (try! (as-contract (stx-transfer? refund-amount tx-sender (get policyholder policy-info))))
      
      (ok refund-amount)
    )
  )
)

;; Read-Only Functions

;; Get policy information
(define-read-only (get-policy-info (policy-id (string-ascii 64)))
  (map-get? insurance-policies { policy-id: policy-id })
)

;; Get weather risk data
(define-read-only (get-weather-risk (location-hash (string-ascii 64)))
  (let
    (
      (current-time stacks-block-height)
      (recent-data (map-get? weather-conditions { location-hash: location-hash, timestamp: current-time }))
    )
    (default-to u100 ;; Default medium risk
      (match recent-data
        data (some (get risk-level data))
        none
      )
    )
  )
)

;; Get route risk data
(define-read-only (get-route-risk (route-hash (string-ascii 64)))
  (default-to u100 ;; Default medium risk
    (match (map-get? route-risk-assessment { route-hash: route-hash })
      data (some (get risk-score data))
      none
    )
  )
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-policies: (var-get total-policies),
    total-premiums-collected: (var-get total-premiums-collected),
    contract-active: (var-get contract-active),
    base-coverage-amount: (var-get base-coverage-amount)
  }
)

;; Get device statistics
(define-read-only (get-device-stats (device-id (string-ascii 64)))
  (map-get? policy-stats { device-id: device-id })
)

;; Private Functions

;; Calculate weather risk multiplier
(define-private (get-weather-multiplier (risk-level uint))
  (if (<= risk-level u30)
    LOW_RISK_MULTIPLIER
    (if (>= risk-level u80)
      HIGH_RISK_MULTIPLIER
      u100
    )
  )
)

;; Calculate route risk multiplier
(define-private (get-route-multiplier (risk-score uint))
  (if (<= risk-score u40)
    LOW_RISK_MULTIPLIER
    (if (>= risk-score u75)
      HIGH_RISK_MULTIPLIER
      u100
    )
  )
)

;; Calculate safety score multiplier
(define-private (get-safety-multiplier (safety-score uint))
  (if (>= safety-score u90)
    u70  ;; 30% discount for excellent safety
    (if (<= safety-score u50)
      u150 ;; 50% penalty for poor safety
      u100 ;; Standard rate for average safety
    )
  )
)

;; Calculate weather risk level
(define-private (calculate-weather-risk
  (temperature int)
  (precipitation uint)
  (wind-speed uint)
  (visibility uint)
  (condition-type (string-ascii 20))
)
  (let
    (
      (temp-risk (if (or (< temperature -50) (> temperature 400)) u30 u0)) ;; -5C or 40C
      (precip-risk (if (> precipitation u500) u25 u0)) ;; 5mm+
      (wind-risk (if (> wind-speed u300) u20 u0)) ;; 30km/h+
      (visibility-risk (if (< visibility u500) u25 u0)) ;; Less than 500m
    )
    (+ u0 temp-risk precip-risk wind-risk visibility-risk)
  )
)

;; Calculate route risk score
(define-private (calculate-route-risk
  (traffic-density uint)
  (road-quality uint)
  (accident-history uint)
  (bike-lane-coverage uint)
  (night-lighting uint)
)
  (let
    (
      (traffic-risk (/ traffic-density u4)) ;; Scale traffic density
      (road-risk (- u25 (/ road-quality u4))) ;; Inverse of road quality
      (accident-risk (* accident-history u5)) ;; Scale accident history
      (lane-safety (- u25 (/ bike-lane-coverage u4))) ;; Inverse of bike lane coverage
      (lighting-risk (- u25 (/ night-lighting u4))) ;; Inverse of lighting quality
    )
    (+ traffic-risk road-risk accident-risk lane-safety lighting-risk)
  )
)

