;; Vehicle Telematics Oracle
;; Real-time telematics data from micro-mobility devices for usage and risk tracking
;; This contract collects, stores, and provides telematics data for insurance calculations

;; Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-DEVICE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-DATA (err u102))
(define-constant ERR-DEVICE-ALREADY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-DEVICE-INACTIVE (err u105))
(define-constant ERR-INVALID-LOCATION (err u106))
(define-constant ERR-DATA-TOO-OLD (err u107))
(define-constant ERR-INVALID-SPEED (err u108))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-DEVICES-PER-USER u100)
(define-constant DATA-VALIDITY-PERIOD u86400) ;; 24 hours in seconds
(define-constant MAX-SPEED u120) ;; Max speed in km/h
(define-constant MIN-BATTERY-LEVEL u10) ;; Minimum battery level percentage

;; Data Variables
(define-data-var total-devices uint u0)
(define-data-var total-data-points uint u0)
(define-data-var contract-active bool true)
(define-data-var data-fee uint u1000) ;; Fee in microSTX for data submission

;; Device Registration Data
(define-map device-registry
  { device-id: (string-ascii 64) }
  {
    owner: principal,
    device-type: (string-ascii 20), ;; "scooter", "bike", "ebike"
    manufacturer: (string-ascii 30),
    model: (string-ascii 30),
    registration-block: uint,
    is-active: bool,
    total-distance: uint, ;; in meters
    total-usage-time: uint ;; in seconds
  }
)

;; Telematics Data Storage
(define-map telematics-data
  { device-id: (string-ascii 64), timestamp: uint }
  {
    latitude: int, ;; multiplied by 1000000 for precision
    longitude: int, ;; multiplied by 1000000 for precision
    speed: uint, ;; km/h
    battery-level: uint, ;; percentage
    acceleration: int, ;; m/s^2 * 100
    braking-force: uint, ;; percentage of max braking
    vibration-level: uint, ;; 0-100 scale
    temperature: int, ;; celsius * 10
    usage-duration: uint, ;; seconds since start
    distance-traveled: uint ;; meters since last update
  }
)

;; Device Status Tracking
(define-map device-status
  { device-id: (string-ascii 64) }
  {
    last-update: uint,
    current-trip-id: (optional (string-ascii 32)),
    is-in-use: bool,
    maintenance-required: bool,
    safety-score: uint, ;; 0-100
    trip-count: uint
  }
)

;; Risk Assessment Data
(define-map risk-metrics
  { device-id: (string-ascii 64) }
  {
    hard-braking-events: uint,
    rapid-acceleration-events: uint,
    high-speed-events: uint,
    night-usage-hours: uint,
    weather-risk-exposure: uint,
    collision-near-misses: uint,
    maintenance-violations: uint
  }
)

;; User Device Count
(define-map user-device-count
  { owner: principal }
  { count: uint }
)

;; Authorized Data Providers
(define-map authorized-providers
  { provider: principal }
  { authorized: bool }
)

;; Public Functions

;; Register a new device
(define-public (register-device 
  (device-id (string-ascii 64))
  (device-type (string-ascii 20))
  (manufacturer (string-ascii 30))
  (model (string-ascii 30))
  (owner principal)
)
  (let
    (
      (current-count (default-to u0 (get count (map-get? user-device-count { owner: owner }))))
      (existing-device (map-get? device-registry { device-id: device-id }))
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-none existing-device) ERR-DEVICE-ALREADY-EXISTS)
    (asserts! (< current-count MAX-DEVICES-PER-USER) ERR-INVALID-DATA)
    
    ;; Register the device
    (map-set device-registry
      { device-id: device-id }
      {
        owner: owner,
        device-type: device-type,
        manufacturer: manufacturer,
        model: model,
        registration-block: stacks-block-height,
        is-active: true,
        total-distance: u0,
        total-usage-time: u0
      }
    )
    
    ;; Initialize device status
    (map-set device-status
      { device-id: device-id }
      {
        last-update: u0,
        current-trip-id: none,
        is-in-use: false,
        maintenance-required: false,
        safety-score: u100,
        trip-count: u0
      }
    )
    
    ;; Initialize risk metrics
    (map-set risk-metrics
      { device-id: device-id }
      {
        hard-braking-events: u0,
        rapid-acceleration-events: u0,
        high-speed-events: u0,
        night-usage-hours: u0,
        weather-risk-exposure: u0,
        collision-near-misses: u0,
        maintenance-violations: u0
      }
    )
    
    ;; Update counters
    (map-set user-device-count
      { owner: owner }
      { count: (+ current-count u1) }
    )
    
    (var-set total-devices (+ (var-get total-devices) u1))
    (ok device-id)
  )
)

;; Submit telematics data
(define-public (submit-telematics-data
  (device-id (string-ascii 64))
  (latitude int)
  (longitude int)
  (speed uint)
  (battery-level uint)
  (acceleration int)
  (braking-force uint)
  (vibration-level uint)
  (temperature int)
  (usage-duration uint)
  (distance-traveled uint)
)
  (let
    (
      (device-info (unwrap! (map-get? device-registry { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
      (current-timestamp stacks-block-height)
      (device-status-info (unwrap! (map-get? device-status { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
      (risk-info (unwrap! (map-get? risk-metrics { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
    )
    
    ;; Validate inputs
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (get is-active device-info) ERR-DEVICE-INACTIVE)
    (asserts! (<= speed MAX-SPEED) ERR-INVALID-SPEED)
    (asserts! (<= battery-level u100) ERR-INVALID-DATA)
    (asserts! (<= vibration-level u100) ERR-INVALID-DATA)
    (asserts! (>= latitude -90000000) ERR-INVALID-LOCATION) ;; -90 degrees * 1000000
    (asserts! (<= latitude 90000000) ERR-INVALID-LOCATION)  ;; 90 degrees * 1000000
    (asserts! (>= longitude -180000000) ERR-INVALID-LOCATION) ;; -180 degrees * 1000000
    (asserts! (<= longitude 180000000) ERR-INVALID-LOCATION)  ;; 180 degrees * 1000000
    
    ;; Store telematics data
    (map-set telematics-data
      { device-id: device-id, timestamp: current-timestamp }
      {
        latitude: latitude,
        longitude: longitude,
        speed: speed,
        battery-level: battery-level,
        acceleration: acceleration,
        braking-force: braking-force,
        vibration-level: vibration-level,
        temperature: temperature,
        usage-duration: usage-duration,
        distance-traveled: distance-traveled
      }
    )
    
    ;; Update device status
    (map-set device-status
      { device-id: device-id }
      (merge device-status-info
        {
          last-update: current-timestamp,
          is-in-use: (> speed u0),
          maintenance-required: (or (< battery-level MIN-BATTERY-LEVEL) (> vibration-level u80))
        }
      )
    )
    
    ;; Update device registry with cumulative data
    (map-set device-registry
      { device-id: device-id }
      (merge device-info
        {
          total-distance: (+ (get total-distance device-info) distance-traveled),
          total-usage-time: (+ (get total-usage-time device-info) usage-duration)
        }
      )
    )
    
    ;; Update risk metrics based on data
    (map-set risk-metrics
      { device-id: device-id }
      (merge risk-info
        {
          hard-braking-events: (if (> braking-force u80) (+ (get hard-braking-events risk-info) u1) (get hard-braking-events risk-info)),
          rapid-acceleration-events: (if (> acceleration 300) (+ (get rapid-acceleration-events risk-info) u1) (get rapid-acceleration-events risk-info)),
          high-speed-events: (if (> speed u60) (+ (get high-speed-events risk-info) u1) (get high-speed-events risk-info))
        }
      )
    )
    
    (var-set total-data-points (+ (var-get total-data-points) u1))
    (ok current-timestamp)
  )
)

;; Start a trip
(define-public (start-trip
  (device-id (string-ascii 64))
  (trip-id (string-ascii 32))
)
  (let
    (
      (device-info (unwrap! (map-get? device-registry { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
      (device-status-info (unwrap! (map-get? device-status { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
    )
    
    (asserts! (is-eq tx-sender (get owner device-info)) ERR-UNAUTHORIZED)
    (asserts! (get is-active device-info) ERR-DEVICE-INACTIVE)
    (asserts! (not (get is-in-use device-status-info)) ERR-INVALID-DATA)
    
    (map-set device-status
      { device-id: device-id }
      (merge device-status-info
        {
          current-trip-id: (some trip-id),
          is-in-use: true,
          trip-count: (+ (get trip-count device-status-info) u1)
        }
      )
    )
    
    (ok trip-id)
  )
)

;; End a trip
(define-public (end-trip (device-id (string-ascii 64)))
  (let
    (
      (device-info (unwrap! (map-get? device-registry { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
      (device-status-info (unwrap! (map-get? device-status { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
    )
    
    (asserts! (is-eq tx-sender (get owner device-info)) ERR-UNAUTHORIZED)
    (asserts! (get is-in-use device-status-info) ERR-INVALID-DATA)
    
    (map-set device-status
      { device-id: device-id }
      (merge device-status-info
        {
          current-trip-id: none,
          is-in-use: false
        }
      )
    )
    
    (ok true)
  )
)

;; Deactivate device
(define-public (deactivate-device (device-id (string-ascii 64)))
  (let
    (
      (device-info (unwrap! (map-get? device-registry { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
    )
    
    (asserts! (is-eq tx-sender (get owner device-info)) ERR-UNAUTHORIZED)
    
    (map-set device-registry
      { device-id: device-id }
      (merge device-info { is-active: false })
    )
    
    (ok true)
  )
)

;; Read-Only Functions

;; Get device information
(define-read-only (get-device-info (device-id (string-ascii 64)))
  (map-get? device-registry { device-id: device-id })
)

;; Get latest telematics data
(define-read-only (get-telematics-data (device-id (string-ascii 64)) (timestamp uint))
  (map-get? telematics-data { device-id: device-id, timestamp: timestamp })
)

;; Get device status
(define-read-only (get-device-status (device-id (string-ascii 64)))
  (map-get? device-status { device-id: device-id })
)

;; Get risk metrics
(define-read-only (get-risk-metrics (device-id (string-ascii 64)))
  (map-get? risk-metrics { device-id: device-id })
)

;; Get total statistics
(define-read-only (get-contract-stats)
  {
    total-devices: (var-get total-devices),
    total-data-points: (var-get total-data-points),
    contract-active: (var-get contract-active),
    data-fee: (var-get data-fee)
  }
)

;; Check if device exists and is active
(define-read-only (is-device-active (device-id (string-ascii 64)))
  (match (map-get? device-registry { device-id: device-id })
    device-info (get is-active device-info)
    false
  )
)

;; Get user device count
(define-read-only (get-user-device-count (owner principal))
  (default-to u0 (get count (map-get? user-device-count { owner: owner })))
)

;; Calculate safety score based on risk metrics
(define-read-only (calculate-safety-score (device-id (string-ascii 64)))
  (match (map-get? risk-metrics { device-id: device-id })
    risk-data
    (let
      (
        (hard-braking-penalty (* (get hard-braking-events risk-data) u2))
        (acceleration-penalty (get rapid-acceleration-events risk-data))
        (speed-penalty (* (get high-speed-events risk-data) u3))
        (maintenance-penalty (* (get maintenance-violations risk-data) u5))
        (total-penalty (+ hard-braking-penalty acceleration-penalty speed-penalty maintenance-penalty))
      )
      (if (> total-penalty u100)
        u0
        (- u100 total-penalty)
      )
    )
    u0
  )
)

