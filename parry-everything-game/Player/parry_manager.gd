extends Node
class_name ParryManager

@export var maxParryWindow : float = 0.6
@export var parryCooldownPenaltyTime : float = 0.3
@export var autoParryWindow : float = 0.15
##The timer to keep track of how long we have been parrying
@export var parryTimer : Timer
##The timer to keep track of the cooldown (only triggered if nothing is parried before timeout)
@export var parryCooldownTimer : Timer
@export var perfectParryPauseTimer : Timer
##The timer to keep track of the auto-parry grace period
@export var autoParryTimer : Timer
##The reference to the first person animation manager
@export var normalParrySound : AudioStreamPlayer
@export var perfectParrySound : AudioStreamPlayer
@export var parryFlash : ColorRect

var isParrying : bool = false
var canParry : bool = true
var isInAutoParryWindow : bool = false
var wasAutoParryPerfect : bool = false
var activeParryWindows : Array[Dictionary] = []  # Stores {resource: ParryResource, timer: Timer}

func _ready() -> void:
	SignalBus.dealDamage.connect(receiveDamage)
	parryTimer.wait_time = maxParryWindow
	parryCooldownTimer.wait_time = parryCooldownPenaltyTime
	autoParryTimer.wait_time = autoParryWindow

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("parry_activate") and canParry:
		activateParry()

func receiveDamage(parryResource : ParryResource):
	# Check if we're in the auto-parry window first
	if isInAutoParryWindow:
		_handleAutoParry(parryResource)
		return
	
	match parryResource.parryType:
		ParryResource.ParryType.PARRY_ONE_SHOT:
			dealOneShotParry(parryResource)
		ParryResource.ParryType.PARRY_WINDOW:
			dealParryWindow(parryResource)

func _handleAutoParry(parryResource : ParryResource):
	# Silently treat as successful parry without effects
	# Use the perfect status from the original parry
	if parryResource.successfulParryCallback.is_valid():
		parryResource.successfulParryCallback.call(wasAutoParryPerfect)
	SignalBus.successfullParry.emit(parryResource, wasAutoParryPerfect)

func activateParry():
	isParrying = true
	canParry = false
	# Manual parry cancels auto-parry window
	if isInAutoParryWindow:
		autoParryTimer.stop()
		isInAutoParryWindow = false
		wasAutoParryPerfect = false
	
	fpAnimationManager.playAnimation("FP_Parry_Stance")
	parryTimer.start()
	
	# Check if there are any active parry windows to resolve
	if activeParryWindows.size() > 0:
		_resolveActiveParryWindows()

func dealOneShotParry(parryResource : ParryResource):
	if not isParrying:
		# Player is not parrying, take damage normally
		_onParryFail(parryResource)
		return
	
	# Calculate how much time has elapsed since parry activation
	var elapsedTime = maxParryWindow - parryTimer.time_left
	
	# Check if it's a perfect parry
	if elapsedTime <= parryResource.perfectParryWindow:
		_onPerfectParry(parryResource)
	# Check if it's a normal parry
	elif elapsedTime <= parryResource.normalParryWindow:
		_onNormalParry(parryResource)
	# Parry window missed
	else:
		_onParryFail(parryResource)

func _onNormalParry(parryResource : ParryResource):
	print("Normal")
	# Stop the parry timer since we successfully parried
	parryTimer.stop()
	
	# Play success animation
	fpAnimationManager.playAnimation("FP_Parry_Success")
	normalParrySound.play()
	
	# Reset parry state and allow immediate re-parry
	isParrying = false
	canParry = true
	
	# Start auto-parry window (normal parry)
	isInAutoParryWindow = true
	wasAutoParryPerfect = false
	autoParryTimer.start()
	
	# Call the success callback if it exists (passing false for not perfect)
	if parryResource.successfulParryCallback.is_valid():
		parryResource.successfulParryCallback.call(false)
	SignalBus.successfullParry.emit(parryResource, false)
	
	await get_tree().create_timer(1).timeout
	fpAnimationManager.playAnimation("FP_Idle_Pose")

func _onPerfectParry(parryResource : ParryResource):
	# Stop the parry timer since we successfully parried
	parryTimer.stop()
	
	# Play success animation
	fpAnimationManager.playAnimation("FP_Parry_Success")
	perfectParrySound.play()
	
	# Reset parry state and allow immediate re-parry
	isParrying = false
	canParry = true
	
	# Start auto-parry window (perfect parry)
	isInAutoParryWindow = true
	wasAutoParryPerfect = true
	autoParryTimer.start()
	
	# Call the success callback if it exists (passing true for perfect parry)
	if parryResource.successfulParryCallback.is_valid():
		parryResource.successfulParryCallback.call(true)
	SignalBus.successfullParry.emit(parryResource, true)
	
	get_tree().paused = true
	parryFlash.show()
	
	perfectParryPauseTimer.start()
	await perfectParryPauseTimer.timeout
	
	get_tree().paused = false
	parryFlash.hide()
	
	await get_tree().create_timer(0.3).timeout
	fpAnimationManager.playAnimation("FP_Idle_Pose")

func _onParryFail(parryResource : ParryResource):
	# Call the failing callback if it exists
	if parryResource.failingParryCallback.is_valid():
		parryResource.failingParryCallback.call(false)

func dealParryWindow(parryResource : ParryResource):
	# Create a timer for this parry window
	var windowTimer = Timer.new()
	add_child(windowTimer)
	windowTimer.wait_time = parryResource.normalParryWindow
	windowTimer.one_shot = true
	
	# Store the window data
	var windowData = {
		"resource": parryResource,
		"timer": windowTimer
	}
	activeParryWindows.append(windowData)
	
	# Connect the timeout signal
	windowTimer.timeout.connect(_onParryWindowTimeout.bind(windowData))
	windowTimer.start()
	
	# If player is already in parry stance, resolve immediately
	if isParrying:
		_resolveActiveParryWindows()

func _resolveActiveParryWindows():
	if activeParryWindows.size() == 0:
		return
	
	var isPerfectParry = false
	var successfulWindows : Array[Dictionary] = []
	
	# Check each active window
	for windowData in activeParryWindows:
		var parryResource : ParryResource = windowData.resource
		var timer : Timer = windowData.timer
		var elapsedTime = timer.wait_time - timer.time_left
		
		# Check if it's within parry windows
		if elapsedTime <= parryResource.perfectParryWindow:
			isPerfectParry = true
			successfulWindows.append(windowData)
		elif elapsedTime <= parryResource.normalParryWindow:
			successfulWindows.append(windowData)
	
	# If we successfully parried at least one window
	if successfulWindows.size() > 0:
		# Clean up all active windows (both successful and failed)
		_cleanupAllWindows()
		
		# Stop the parry timer
		parryTimer.stop()
		
		# Trigger the appropriate parry response
		if isPerfectParry:
			_onPerfectParryWindows(successfulWindows)
		else:
			_onNormalParryWindows(successfulWindows)
	else:
		# Player pressed parry but all windows expired, clean them up
		_cleanupAllWindows()

func _onNormalParryWindows(successfulWindows : Array[Dictionary]):
	# Play success animation
	fpAnimationManager.playAnimation("FP_Parry_Success")
	normalParrySound.play()
	
	# Reset parry state and allow immediate re-parry
	isParrying = false
	canParry = true
	
	# Start auto-parry window (normal parry)
	isInAutoParryWindow = true
	wasAutoParryPerfect = false
	autoParryTimer.start()
	
	# Call callbacks for all successful windows
	for windowData in successfulWindows:
		var parryResource : ParryResource = windowData.resource
		if parryResource.successfulParryCallback.is_valid():
			parryResource.successfulParryCallback.call(false)
		SignalBus.successfullParry.emit(parryResource, false)
	
	await get_tree().create_timer(1).timeout
	fpAnimationManager.playAnimation("FP_Idle_Pose")

func _onPerfectParryWindows(successfulWindows : Array[Dictionary]):
	# Play success animation
	fpAnimationManager.playAnimation("FP_Parry_Success")
	perfectParrySound.play()
	
	# Reset parry state and allow immediate re-parry
	isParrying = false
	canParry = true
	
	# Start auto-parry window (perfect parry)
	isInAutoParryWindow = true
	wasAutoParryPerfect = true
	autoParryTimer.start()
	
	# Call callbacks for all successful windows
	for windowData in successfulWindows:
		var parryResource : ParryResource = windowData.resource
		if parryResource.successfulParryCallback.is_valid():
			parryResource.successfulParryCallback.call(true)
		SignalBus.successfullParry.emit(parryResource, true)
	
	get_tree().paused = true
	parryFlash.show()
	
	perfectParryPauseTimer.start()
	await perfectParryPauseTimer.timeout
	
	get_tree().paused = false
	parryFlash.hide()
	
	await get_tree().create_timer(0.3).timeout
	fpAnimationManager.playAnimation("FP_Idle_Pose")

func _onParryWindowTimeout(windowData : Dictionary):
	# Remove this specific window from active windows
	var index = activeParryWindows.find(windowData)
	if index != -1:
		activeParryWindows.remove_at(index)
		
		# Clean up the timer
		var timer : Timer = windowData.timer
		timer.queue_free()
		
		# Call the failing callback
		var parryResource : ParryResource = windowData.resource
		if parryResource.failingParryCallback.is_valid():
			parryResource.failingParryCallback.call(false)

func _cleanupAllWindows():
	# Stop and free all window timers
	for windowData in activeParryWindows:
		var timer : Timer = windowData.timer
		timer.stop()
		timer.queue_free()
	
	# Clear the array
	activeParryWindows.clear()

func _on_parry_timer_timeout() -> void:
	# Player missed the parry window, apply cooldown penalty
	isParrying = false
	fpAnimationManager.playAnimation("FP_Idle_Pose")
	parryCooldownTimer.start()

func _on_parry_cooldown_timer_timeout() -> void:
	# Cooldown is over, player can parry again
	canParry = true

func _on_auto_parry_timer_timeout() -> void:
	# Auto-parry window expired
	isInAutoParryWindow = false
	wasAutoParryPerfect = false
