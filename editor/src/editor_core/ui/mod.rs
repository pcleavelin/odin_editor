// TODO: remove when things are actully used
#![allow(dead_code)]
use std::collections::HashMap;

const ROOT_NODE: &str = "root";

type NodeIndex = usize;

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
        NodeKey(format!("{}:{label}", cx.node_ref(cx.current_parent).label))
    }
}

#[derive(Debug, Default, Clone, Copy)]
enum SemanticSize {
    #[default]
    FitText,
    ChildrenSum,
    Fill,
    Exact(i32),
    PercentOfParent(i32),
}

#[derive(Debug, Default)]
enum Axis {
    #[default]
    Horizontal,
    Vertical,
}

#[derive(Debug, Default)]
struct PersistentNodeData {
    axis: Axis,
    semantic_size: [SemanticSize; 2],
    computed_size: [i32; 2],
    computed_pos: [i32; 2],
}

#[derive(Debug)]
struct FrameNode {
    key: NodeKey,
    label: String,

    first: Option<NodeIndex>,
    last: Option<NodeIndex>,
    next: Option<NodeIndex>,
    prev: Option<NodeIndex>,
    parent: Option<NodeIndex>,
}

impl FrameNode {
    fn root() -> Self {
        Self {
            key: NodeKey::root(),
            label: "root".to_string(),
            first: None,
            last: None,
            next: None,
            prev: None,
            parent: None,
        }
    }
}

pub struct Context {
    persistent: HashMap<NodeKey, PersistentNodeData>,
    frame_nodes: Vec<FrameNode>,

    current_parent: NodeIndex,
    root_node: NodeIndex,
}

impl Context {
    pub fn new() -> Self {
        let mut nodes = HashMap::new();
        nodes.insert(NodeKey::root(), PersistentNodeData::default());

        Self {
            persistent: nodes,
            frame_nodes: vec![FrameNode::root()],
            current_parent: 0,
            root_node: 0,
        }
    }

    // TODO: refactor to not panic, return option
    /// Panics on out-of-bounds index
    fn node_ref(&self, index: NodeIndex) -> &FrameNode {
        self.frame_nodes
            .get(index)
            .expect("this is a bug, index should be valid")
    }

    // TODO: refactor to not panic, return option
    /// Panics on out-of-bounds index
    fn node_ref_mut(&mut self, index: NodeIndex) -> &mut FrameNode {
        self.frame_nodes
            .get_mut(index)
            .expect("this is a bug, index should be valid")
    }

    fn node_first_ref_mut(&mut self, index: NodeIndex) -> Option<&mut FrameNode> {
        self.node_ref_mut(index)
            .first
            .map(|index| self.node_ref_mut(index))
    }

    fn node_last_ref_mut(&mut self, index: NodeIndex) -> Option<&mut FrameNode> {
        self.node_ref_mut(index)
            .last
            .map(|index| self.node_ref_mut(index))
    }

    fn node_next_ref_mut(&mut self, index: NodeIndex) -> Option<&mut FrameNode> {
        self.node_ref_mut(index)
            .next
            .map(|index| self.node_ref_mut(index))
    }

    fn node_prev_ref_mut(&mut self, index: NodeIndex) -> Option<&mut FrameNode> {
        self.node_ref_mut(index)
            .prev
            .map(|index| self.node_ref_mut(index))
    }

    pub fn make_node(&mut self, label: impl ToString) -> NodeIndex {
        let label = label.to_string();
        let key = NodeKey::new(self, &label);

        if let Some(_node) = self.persistent.get(&key) {
            // TODO: check for last_interacted_index and invalidate persistent data
        } else {
            self.persistent
                .insert(key.clone(), PersistentNodeData::default());
        }

        let frame_node = FrameNode {
            key,
            label,
            first: None,
            last: None,
            next: None,
            prev: self.node_ref(self.current_parent).last,
            parent: Some(self.current_parent),
        };
        self.frame_nodes.push(frame_node);
        let this_index = self.frame_nodes.len() - 1;

        if let Some(parent_last) = self.node_last_ref_mut(self.current_parent) {
            parent_last.next = Some(this_index);
        }

        let parent_node = self.node_ref_mut(self.current_parent);
        if parent_node.first.is_none() {
            parent_node.first = Some(this_index);
        }
        parent_node.last = Some(this_index);

        this_index
    }

    pub fn push_parent(&mut self, key: NodeIndex) {
        self.current_parent = key;
    }
    pub fn pop_parent(&mut self) {
        self.current_parent = self.node_ref(self.current_parent).parent.unwrap_or(0);
    }

    pub fn debug_print(&self) {
        let iter = NodeIter::from_index(&self.frame_nodes, 0);

        for node in iter {
            eprintln!("{node:?}");
        }
    }

    pub fn update_layout(&mut self) {
        let iter = NodeIter::from_index(&self.frame_nodes, 0);
        for node in iter {
            let Some(persistent) = self.persistent.get_mut(&node.key) else {
                continue;
            };

            if let Some(parent_index) = node.parent {
                let parent_node = self.node_ref(parent_index);
            }
        }
    }
}

struct NodeIter<'a> {
    frame_nodes: &'a [FrameNode],
    index: NodeIndex,
    reached_end: bool,
}

impl<'a> NodeIter<'a> {
    fn from_index(frame_nodes: &'a [FrameNode], index: NodeIndex) -> Self {
        Self {
            frame_nodes,
            index,
            reached_end: false,
        }
    }
}

impl<'a> Iterator for NodeIter<'a> {
    type Item = &'a FrameNode;

    fn next(&mut self) -> Option<Self::Item> {
        if self.reached_end {
            return None;
        }

        if let Some(node) = self.frame_nodes.get(self.index) {
            if let Some(first) = node.first {
                self.index = first;
            } else if let Some(next) = node.next {
                self.index = next;
            } else if let Some(parent_next) = node
                .parent
                .and_then(|index| self.frame_nodes.get(index))
                .and_then(|node| node.next)
            {
                self.index = parent_next;
            } else {
                self.reached_end = true;
            }

            return Some(node);
        }

        None
    }
}
