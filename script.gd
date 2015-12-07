extends Node

var data = {}
var node_pos = 0

var nodes = []
var wait = null

class Condition:
	var name
	var compare
	var value
	func write():
		var d = {}
		d["compare"] = compare
		d["name"] = name
		d["value"] = value
		return d
	func read(d):
		compare = d["compare"]
		name = d["name"]
		value = d["value"]
	func test(data):
		if compare == "exists":
			if data.has(name):
				return value
			return not value
		var v = null
		if data.has(name):
			v = data[name]
		if compare == "==":
			return (v == value)
		elif compare == "!=":
			return (v != value)
		if v == null:
			v = 0
		elif compare == "<=":
			return (v <= value)
		elif compare == ">=":
			return (v >= value)
		elif compare == "<":
			return (v < value)
		elif compare == ">":
			return (v > value)

class Message:
	var text
	var speaker
	func write():
		var d = {}
		d["type"] = "message"
		d["text"] = text
		d["speaker"] = speaker
		return d
	func read(d):
		text = d["text"]
		speaker = d["speaker"]

class Choice:
	class Option:
		var text
		var position
		var condition
	var options
	var end
	func _init():
		options = []
	func write():
		var d = {}
		var a = []
		for opt in options:
			var o = {}
			o["text"] = opt.text
			o["position"] = opt.position
			if opt.condition == null:
				o["condition"] = null
			else:
				o["condition"] = opt.condition.write()
			a.append(o)
		d["type"] = "choice"
		d["options"] = a
		return d
	func read(d):
		options.clear()
		for o in d["options"]:
			var opt = Option.new()
			opt.text = o["text"]
			opt.position = o["position"]
			if o["condition"] != null:
				opt.condition = Condition.new()
				opt.condition.read(o["condition"])
			else:
				opt.condition = null
			options.append(opt)

class ConditionBlock:
	class Branch:
		var position
		var condition
	var branches
	var else_position
	var end
	func _init():
		branches = []
		else_position = null
	func write():
		var d = {}
		var a = []
		for branch in branches:
			var b = {}
			b["position"] = branch.position
			b["condition"] = branch.condition.write()
			a.append(b)
		d["type"] = "condition_block"
		d["branches"] = a
		d["else"] = else_position
		return d
	func read(d):
		branches.clear()
		for b in d["branches"]:
			var branch = Branch.new()
			branch.position = b["position"]
			branch.condition = Condition.new()
			branch.condition.read(b["condition"])
			branches.append(branch)
		else_position = d["else"]
	func test(data):
		for b in branches:
			if b.condition.test(data):
				return b.position
		return else_position

class Marker:
	var name
	var operation
	var value
	func write():
		var d = {}
		d["type"] = "marker"
		d["name"] = name
		d["operation"] = operation
		d["value"] = value
		return d
	func read(d):
		name = d["name"]
		operation = d["operation"]
		value = d["value"]
	func execute(data):
		if operation == "=":
			data[name] = value
		else:
			if not data.has(name):
				if operation == "flag":
					data[name] = null
					return
				data[name] = 0
			elif operation == "+":
				data[name] += value
			elif operation == "-":
				data[name] -= value

class Jump:
	var position
	func write():
		var d = {}
		d["type"] = "jump"
		d["position"] = position
		return d
	func read(d):
		position = d["position"]

func start(pos = 0):
	node_pos = pos
	return _step()

func _step():
	while wait == null and node_pos < nodes.size():
		var n = nodes[node_pos]
		if n extends Message:
			wait = n
		elif n extends Choice:
			wait = n
		elif n extends ConditionBlock:
			node_pos = n.test(data)
		elif n extends Marker:
			n.execute(data)
			node_pos += 1
		elif n extends Jump:
			node_pos = n.position
	return wait

func continue_message():
	if wait != null and wait extends Message:
		node_pos += 1
		wait = null
		return _step()

func continue_choice(choice):
	if wait != null and wait extends Choice:
		node_pos = wait.options[choice].position
		wait = null
		return _step()

func eof():
	if node_pos >= nodes.size():
		return true

func export_json():
	var d = {"nodes":[]}
	for n in nodes:
		d["nodes"].append(n.write())
	return d.to_json()

func import_json(string):
	nodes.clear()
	var d = {}
	d.parse_json(string)
	for n in d["nodes"]:
		if n["type"] == "message":
			var node = Message.new()
			node.read(n)
			nodes.append(node)
		if n["type"] == "choice":
			var node = Choice.new()
			node.read(n)
			nodes.append(node)
		if n["type"] == "condition_block":
			var node = ConditionBlock.new()
			node.read(n)
			nodes.append(node)
		if n["type"] == "marker":
			var node = Marker.new()
			node.read(n)
			nodes.append(node)
		if n["type"] == "jump":
			var node = Jump.new()
			node.read(n)
			nodes.append(node)
	return d.to_json()

func open_file(path):
	var file = File.new()
	file.open(path, File.READ)
	if file.is_open():
		_parse_script(file.get_as_text())

class _BlockEnd:
	var block
	func _init(b):
		block = weakref(b)

class _LabelJump:
	var name
	func _init(n):
		name = n

func _new_regex(pattern):
	var re = RegEx.new()
	re.compile(pattern)
	return re

func _parse_condition(string, re_int, re_flag):
	if re_int.find(string) == 0:
		var c = Condition.new()
		c.name = re_int.get_capture(1)
		c.compare = re_int.get_capture(2)
		c.value = int(re_int.get_capture(3))
		return c
	elif re_flag.find(string) == 0:
		var c = Condition.new()
		c.name = re_flag.get_capture(2)
		c.compare = "exists"
		if re_flag.get_capture(1) != "":
			c.value = false
		else:
			c.value = true
		return c
	else:
		print("invalid condition: ", string)
		return null

func _parse_script(src):
	var re_indent = _new_regex("^\\t+")
	var re_message = _new_regex("^:(?:<([^>]*)>)?\\s*(.*)$")
	var re_option = _new_regex("^>(?:{([^}]+)})?\\s*(.*)$")
	var re_if = _new_regex("^#(?:if|elif)\\s+(.+)$")
	var re_flag = _new_regex("^\\$\\s*([A-Za-z_]\\w*)$")
	var re_set_int = _new_regex("^\\$\\s*([A-Za-z_]\\w*)\\s*(=|\\+|-)\\s*(-?\\d+)$")
	var re_label = _new_regex("^@\\s*(\\w*)$")
	var re_jump = _new_regex("^#jump\\s+@?(\\w*)$")
	var re_cond_int = _new_regex("^([A-Za-z_]\\w*)\\s*(==|<=|>=|<|>|!=)\\s*(-?\\d+)$")
	var re_cond_flag = _new_regex("^(!\\s+)?([A-Za-z_]\\w*)$")
	nodes.clear()
	var labels = {}
	var stack = []
	var stack_last = null
	var lines = src.split("\n")
	for l in lines:
		var indent = 0
		if re_indent.find(l) == 0:
			indent = re_indent.get_capture(0).length()
		l = l.strip_edges()
		if l.length() == 0:
			continue
		if indent > stack.size():
			print("extra indent")
			break
		while indent < stack.size():
			if stack[0] extends Choice or stack[0] extends ConditionBlock:
				stack[0].end = nodes.size()
				stack_last = stack[0]
				stack.remove(0)
		if l.begins_with(">"):
			if re_option.find(l) == 0:
				if stack_last != null and stack_last extends Choice:
					stack.insert(0, stack_last)
				else:
					stack.insert(0, Choice.new())
					nodes.push_back(stack[0])
				stack_last = null
				if stack[0].options.size() > 0:
					nodes.push_back(_BlockEnd.new(stack[0]))
				var o = Choice.Option.new()
				o.text = re_option.get_capture(2)
				o.position = nodes.size()
				var cond = re_option.get_capture(1).strip_edges()
				if cond.length() > 0:
					o.condition = _parse_condition(cond, re_cond_int, re_cond_flag)
				stack[0].options.append(o)
				continue
		elif l.begins_with("#if") or l.begins_with("#elif") or l == "#else":
			if l == "#else" or re_if.find(l) == 0:
				if l.begins_with("#if"):
					stack.insert(0, ConditionBlock.new())
					nodes.push_back(stack[0])
				elif stack_last != null and stack_last extends ConditionBlock:
					stack.insert(0, stack_last)
				else:
					print("stray else/elif statement: ", l)
					continue
				stack_last = null
				if stack[0].branches.size() > 0:
					nodes.push_back(_BlockEnd.new(stack[0]))
				if l != "#else":
					var b = ConditionBlock.Branch.new()
					b.position = nodes.size()
					b.condition = _parse_condition(re_if.get_capture(1), re_cond_int, re_cond_flag)
					if b.condition != null:
						stack[0].branches.append(b)
					continue
				else:
					if stack[0].else_position == null:
						stack[0].else_position = nodes.size()
					else:
						print("extra else statement: ", l)
					continue
		stack_last = null
		if l.begins_with(":"):
			if re_message.find(l) == 0:
				var m = Message.new()
				m.text = re_message.get_capture(2)
				m.speaker = re_message.get_capture(1).strip_edges()
				nodes.push_back(m)
				continue
		elif l.begins_with("$"):
			if re_set_int.find(l) == 0:
				var m = Marker.new()
				m.name = re_set_int.get_capture(1)
				m.operation = re_set_int.get_capture(2)
				m.value = int(re_set_int.get_capture(3))
				nodes.push_back(m)
				continue
			elif re_flag.find(l) == 0:
				var m = Marker.new()
				m.name = re_flag.get_capture(1)
				m.operation = "flag"
				nodes.push_back(m)
				continue
		elif l.begins_with("@"):
			if re_label.find(l) == 0:
				var name = re_label.get_capture(1)
				if labels.has(name):
					print("label already in use: ", name)
				else:
					labels[name] = nodes.size()
				continue
		elif l.begins_with("#jump"):
			if re_jump.find(l) == 0:
				nodes.push_back(_LabelJump.new(re_jump.get_capture(1)))
				continue
		print("invalid format: ", l)
	while stack.size() > 0:
		if stack[0] extends Choice or stack[0] extends ConditionBlock:
			stack[0].end = nodes.size()
		stack.remove(0)
	for i in range(nodes.size()):
		if nodes[i] extends _LabelJump:
			var name = nodes[i].name
			nodes.remove(i)
			if labels.has(name):
				var j = Jump.new()
				j.position = labels[name]
				nodes.insert(i, j)
			else:
				print("label not found: ", name)
		elif nodes[i] extends _BlockEnd:
			var j = Jump.new()
			j.position = nodes[i].block.get_ref().end
			nodes.remove(i)
			nodes.insert(i, j)
		elif nodes[i] extends ConditionBlock:
			if nodes[i].else_position == null:
				nodes[i].else_position = nodes[i].end
