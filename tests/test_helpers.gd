extends RefCounted


static func wait_for_gameplay(root_node: Node) -> Node:
	for _frame in 180:
		var gameplay := root_node.find_child("GameplayScreen", true, false)
		if gameplay != null and not gameplay.is_queued_for_deletion() and gameplay.visible:
			return gameplay
		await root_node.get_tree().process_frame
	return null
