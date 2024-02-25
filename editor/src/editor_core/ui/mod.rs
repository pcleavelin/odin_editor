use std::collections::HashMap;

const ROOT_NODE: &str = "root";

#[derive(Clone, Hash, Eq, PartialEq)]
pub struct NodeKey(String);
impl std::fmt::Display for NodeKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::fmt::Debug for NodeKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self}")
    }
}

impl NodeKey {
    fn root() -> Self {
        Self(ROOT_NODE.to_string())
    }

    pub fn new(cx: &Context, label: &str) -> Self {
        NodeKey(format!("{}:{label}", cx.current_parent))
    }
}

#[derive(Debug)]
struct Node {
    first: Option<NodeKey>,
    last: Option<NodeKey>,
    next: Option<NodeKey>,
    prev: Option<NodeKey>,

    parent: Option<NodeKey>,

    label: String,
}

pub struct Context {
    persistent_nodes: HashMap<NodeKey, Node>,

    current_parent: NodeKey,
    root_node: NodeKey,
}

impl Context {
    pub fn new() -> Self {
        let mut nodes = HashMap::new();
        nodes.insert(
            NodeKey::root(),
            Node {
                first: None,
                last: None,
                next: None,
                prev: None,
                parent: None,
                label: "root".to_string(),
            },
        );

        Self {
            persistent_nodes: nodes,
            current_parent: NodeKey::root(),
            root_node: NodeKey::root(),
        }
    }

    fn parent_key(&self, key: &NodeKey) -> Option<NodeKey> {
        self.persistent_nodes
            .get(key)
            .and_then(|n| n.parent.clone())
    }
    fn first_key(&self, key: &NodeKey) -> Option<NodeKey> {
        self.first_key_ref(key).cloned()
    }
    fn last_key(&self, key: &NodeKey) -> Option<NodeKey> {
        self.persistent_nodes.get(key).and_then(|n| n.last.clone())
    }
    fn next_key(&self, key: &NodeKey) -> Option<NodeKey> {
        self.next_key_ref(key).cloned()
    }
    fn prev_key(&self, key: &NodeKey) -> Option<NodeKey> {
        self.persistent_nodes.get(key).and_then(|n| n.prev.clone())
    }

    fn first_key_ref(&self, key: &NodeKey) -> Option<&NodeKey> {
        self.persistent_nodes
            .get(key)
            .and_then(|n| n.first.as_ref())
    }
    fn next_key_ref(&self, key: &NodeKey) -> Option<&NodeKey> {
        self.persistent_nodes.get(key).and_then(|n| n.next.as_ref())
    }

    pub fn make_node(&mut self, label: impl ToString) -> NodeKey {
        let label = label.to_string();
        let key = NodeKey::new(self, &label);

        if let Some(_node) = self.persistent_nodes.get(&key) {
            // TODO: check for last_interacted_index
        } else {
            let node = Node {
                first: None,
                last: None,
                next: None,
                prev: self.last_key(&self.current_parent),
                parent: Some(self.current_parent.clone()),

                label,
            };
            self.persistent_nodes.insert(key.clone(), node);
        }

        // Update tree references
        if let Some(parent_node) = self.persistent_nodes.get_mut(&self.current_parent) {
            if parent_node.first.is_none() {
                parent_node.first = Some(key.clone());
            }

            // NOTE(pcleavelin): `parent_node.last` must be updated before the below mutable
            // borrow so the mutable reference above is un-borrowed by then
            let last_before_update = parent_node.last.clone();
            parent_node.last = Some(key.clone());

            if let Some(parent_node_last) = last_before_update {
                if let Some(last_node) = self.persistent_nodes.get_mut(&parent_node_last) {
                    last_node.next = Some(key.clone());
                }
            }
        }

        key
    }

    pub fn push_parent(&mut self, key: NodeKey) {
        self.current_parent = key;
    }
    pub fn pop_parent(&mut self) {
        self.current_parent = self
            .parent_key(&self.current_parent)
            .unwrap_or(NodeKey::root());
    }

    pub fn debug_print(&self) {
        let root_node = NodeKey::root();
        let iter = NodeIter::from_key(self, self.first_key_ref(&root_node).unwrap());

        for node in iter {
            eprintln!("{node:?}");
        }
    }
}

struct NodeIter<'a> {
    cx: &'a Context,
    current_key: &'a NodeKey,
    reached_end: bool,
}

impl<'a> NodeIter<'a> {
    fn from_key(cx: &'a Context, key: &'a NodeKey) -> Self {
        Self {
            cx,
            current_key: key,
            reached_end: false,
        }
    }
}

impl<'a> Iterator for NodeIter<'a> {
    type Item = &'a Node;

    fn next(&mut self) -> Option<Self::Item> {
        if self.reached_end {
            return None;
        }

        if let Some(node) = self.cx.persistent_nodes.get(self.current_key) {
            if let Some(first) = node.first.as_ref() {
                self.current_key = first;
            } else if let Some(next) = node.next.as_ref() {
                self.current_key = next;
            } else if let Some(parent) = node.parent.as_ref() {
                if let Some(parent_next) = self.cx.next_key_ref(parent) {
                    self.current_key = parent_next;
                } else {
                    self.reached_end = true;
                }
            } else {
                self.reached_end = true;
            }

            return Some(node);
        }

        None
    }
}
