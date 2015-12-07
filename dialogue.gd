extends Control

var script = preload("res://script.gd").new()
var n_message_panel
var n_speaker_panel
var n_message_text
var n_speaker_text

var message_length = 0
var message_timer = 0.0
var message_tick = 0.02

var n_choices_container
var n_choices_list
var n_choices_button

func _ready():
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	get_node("message").connect("input_event", self, "_message_input")

	n_message_panel = get_node("message/panel")
	n_speaker_panel = get_node("message/panel/speaker")
	n_message_text = n_message_panel.get_node("text")
	n_speaker_text = n_speaker_panel.get_node("text")

	n_choices_container = get_node("choices")
	n_choices_list = get_node("choices/list")
	n_choices_button = n_choices_list.get_node("button").duplicate()
	for c in n_choices_list.get_children():
		n_choices_list.remove_child(c)

	script.open_file("res://demo.txt")
	_next(script.start(0))

func _process(delta):
	message_timer = max(0.0, message_timer - delta)
	n_message_text.set_visible_characters(message_length - int(message_timer / message_tick))

func _unhandled_input(event):
	if event.is_action("message_next") and event.is_pressed() and not event.is_echo():
		_continue_message()

func _message_input(event):
	if event.type == InputEvent.MOUSE_BUTTON:
		if event.button_index == 1 and event.is_pressed():
			_continue_message()

func _continue_message():
	if message_timer > 0.0:
		n_message_text.set_percent_visible(1)
		message_timer = 0.0
	else:
		_next(script.continue_message())

func _continue_choice(i):
	_next(script.continue_choice(i))

func _next(node):
	if node != null:
		if node extends script.Message:
			n_choices_container.hide()
			n_message_panel.show()
			n_message_text.set_visible_characters(0)
			n_message_text.set_text(node.text)
			message_length = n_message_text.get_total_character_count()
			message_timer = message_tick * message_length
			if node.speaker.length() > 0:
				n_speaker_text.set_text(node.speaker)
				n_speaker_panel.show()
			else:
				n_speaker_panel.hide()
		if node extends script.Choice:
			n_message_panel.hide()
			n_choices_container.show()
			for c in n_choices_list.get_children():
				n_choices_list.remove_child(c)
			for i in range(node.options.size()):
				var button = n_choices_button.duplicate()
				button.set_text(node.options[i].text)
				n_choices_list.add_child(button)
				button.connect("pressed", self, "_continue_choice", [i])
				if i == 0:
					button.grab_focus()
