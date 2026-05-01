class_name SplashScreen extends Node2D

signal splash_completed


func _ready() -> void:
	splash_completed.emit.call_deferred()


func initialize(_data: Dictionary) -> void:
	pass
