// TODO: remove when things are actully used
#![allow(dead_code)]
use std::collections::HashMap;

const ROOT_NODE: &str = "root";
const FONT_WIDTH: usize = 8;
const FONT_HEIGHT: usize = 16;

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
        NodeKey(format!("{}:{label}", cx.node_ref(cx.current_parent).key))
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub enum SemanticSize {
    #[default]
    FitText,
    ChildrenSum,
    Fill,
    Exact(i32),
    PercentOfParent(i32),
}

#[derive(Debug, Default, Clone, Copy)]
#[repr(usize)]
pub enum Axis {
    #[default]
    Horizontal,
    Vertical,
}

#[derive(Debug, Default, Clone, Copy)]
pub struct Size {
    pub axis: Axis,
    pub semantic_size: [SemanticSize; 2],
    pub computed_size: [i32; 2],
    pub computed_pos: [i32; 2],
}

#[derive(Debug, Default)]
pub struct PersistentNodeData {
    pub label: String,
    pub size: Size,
}

#[derive(Debug)]
struct FrameNode {
    index: NodeIndex,
    key: NodeKey,
    label: String,

    size: Size,

    first: Option<NodeIndex>,
    last: Option<NodeIndex>,
    next: Option<NodeIndex>,
    prev: Option<NodeIndex>,
    parent: Option<NodeIndex>,
}

impl FrameNode {
    fn root() -> Self {
        Self {
            index: 0,
            key: NodeKey::root(),
            label: "root".to_string(),
            size: Size::default(),
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

    pub fn node_iter(&self) -> impl Iterator<Item = &'_ PersistentNodeData> {
        PersistentIter::from_context(self)
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
            unimplemented!("no persistent nodes for you");
        } else {
            self.persistent.insert(
                key.clone(),
                PersistentNodeData {
                    label: label.clone(),
                    ..Default::default()
                },
            );
        }

        let this_index = self.frame_nodes.len();
        let frame_node = FrameNode {
            size: self.persistent.get(&key).expect("guaranteed to exist").size,

            index: this_index,
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

    pub fn _make_node_with_semantic_size(
        &mut self,
        label: impl ToString,
        semantic_size: [SemanticSize; 2],
    ) -> NodeIndex {
        let index = self.make_node(label);

        let node = self.node_ref_mut(index);
        node.size.semantic_size = semantic_size;

        index
    }

    pub fn push_parent(&mut self, key: NodeIndex) {
        self.current_parent = key;
    }
    pub fn pop_parent(&mut self) {
        let Some(parent) = self.frame_nodes.last().and_then(|node| node.parent) else {
            return;
        };

        self.current_parent = self.node_ref(parent).parent.unwrap_or(0);
    }

    pub fn debug_print(&self) {
        let iter = NodeIter::from_index(&self.frame_nodes, 0, true);

        for node in iter {
            let Some(_persistent) = self.persistent.get(&node.key) else {
                continue;
            };
            eprintln!("{node:#?}");
        }
    }

    pub fn prune(&mut self) {
        self.frame_nodes.clear();
    }

    fn ancestor_size(&self, index: NodeIndex, axis: Axis) -> i32 {
        if let Some(parent) = self.node_ref(index).parent {
            let parent_node = self.node_ref(parent);
            match parent_node.size.semantic_size[axis as usize] {
                SemanticSize::FitText
                | SemanticSize::Fill
                | SemanticSize::Exact(_)
                | SemanticSize::PercentOfParent(_) => {
                    return parent_node.size.computed_size[axis as usize];
                }

                SemanticSize::ChildrenSum => return self.ancestor_size(parent, axis),
            }
        }

        // TODO: change this panic to something else less catastrophic
        // should never get here if everything else is working properly
        panic!("no ancestor size");
        0
    }

    pub fn update_layout(&mut self, canvas_size: [i32; 2], index: NodeIndex) {
        let mut post_compute_horizontal = false;
        let mut post_compute_vertical = false;

        {
            let mut parent_axis = Axis::default();
            if let Some(parent_index) = self.frame_nodes[index].parent {
                let parent_node = self.node_ref(parent_index);

                parent_axis = parent_node.size.axis;
                self.frame_nodes[index].size.computed_pos = parent_node.size.computed_pos;
            }

            if let Some(prev_node) = self.frame_nodes[index]
                .prev
                .map(|index| self.node_ref(index))
            {
                let prev_pos = prev_node.size.computed_pos;
                let prev_size = prev_node.size.computed_size;

                self.frame_nodes[index].size.computed_pos[parent_axis as usize] =
                    prev_pos[parent_axis as usize] + prev_size[parent_axis as usize];
            }

            if self.frame_nodes[index].key.0.as_str() == "root" {
                self.frame_nodes[index].size.computed_size = canvas_size;
            } else {
                match self.frame_nodes[index].size.semantic_size[0] {
                    SemanticSize::FitText => {
                        self.frame_nodes[index].size.computed_size[0] =
                            (self.frame_nodes[index].label.len() * FONT_WIDTH) as i32;
                    }
                    SemanticSize::ChildrenSum => {
                        post_compute_horizontal = true;
                    }
                    SemanticSize::Fill => (),
                    SemanticSize::Exact(size) => {
                        self.frame_nodes[index].size.computed_size[0] = size
                    }
                    SemanticSize::PercentOfParent(percent) => {
                        let size = ((self
                            .ancestor_size(self.frame_nodes[index].index, Axis::Horizontal)
                            as f32)
                            * (percent as f32)
                            / 100.0) as i32;

                        self.frame_nodes[index].size.computed_size[0] = size;
                    }
                }
                match self.frame_nodes[index].size.semantic_size[1] {
                    SemanticSize::FitText => {
                        self.frame_nodes[index].size.computed_size[1] = FONT_HEIGHT as i32;
                    }
                    SemanticSize::ChildrenSum => {
                        post_compute_vertical = true;
                    }
                    SemanticSize::Fill => (),
                    SemanticSize::Exact(size) => {
                        self.frame_nodes[index].size.computed_size[1] = size
                    }
                    SemanticSize::PercentOfParent(percent) => {
                        let size = ((self
                            .ancestor_size(self.frame_nodes[index].index, Axis::Vertical)
                            as f32)
                            * (percent as f32)
                            / 100.0) as i32;

                        self.frame_nodes[index].size.computed_size[Axis::Vertical as usize] = size;
                    }
                }
            }
        }

        // let there be the braces of lifetimes
        {
            if let Some(first_child_index) = self.frame_nodes.get(index).and_then(|node| node.first)
            {
                let mut child_size: [i32; 2] = [0; 2];
                let mut number_of_fills = [1; 2];
                number_of_fills[self.frame_nodes[index].size.axis as usize] = 0;

                let mut i = first_child_index;
                loop {
                    self.update_layout(canvas_size, i);

                    let child_node = self.node_ref(i);
                    if matches!(
                        child_node.size.semantic_size[self.frame_nodes[index].size.axis as usize],
                        SemanticSize::Fill
                    ) {
                        number_of_fills[self.frame_nodes[index].size.axis as usize] += 1;
                    } else {
                        child_size[self.frame_nodes[index].size.axis as usize] += child_node
                            .size
                            .computed_size[self.frame_nodes[index].size.axis as usize];
                    }

                    let Some(next) = self.node_ref(i).next else {
                        break;
                    };

                    i = next;
                }

                // update nodes with `Fill` with their new computed size
                let mut i = first_child_index;
                loop {
                    let node_size = self.frame_nodes[index].size.computed_size;
                    let child_node = self.node_ref_mut(i);
                    for axis in 0..2 {
                        if matches!(child_node.size.semantic_size[axis], SemanticSize::Fill) {
                            child_node.size.computed_size[axis] =
                                (node_size[axis] - child_size[axis]) / number_of_fills[axis];
                        }
                    }

                    self.update_layout(canvas_size, i);

                    let Some(next) = self.node_ref(i).next else {
                        break;
                    };

                    i = next;
                }
            }
        }

        if post_compute_horizontal {
            self.frame_nodes[index].size.computed_size[Axis::Horizontal as usize] = 0;

            if let Some(first_child_index) = self.node_ref(index).first {
                let mut node_size = self.frame_nodes[index].size.computed_size;
                for child_node in NodeIter::from_index(&self.frame_nodes, first_child_index, false)
                {
                    let child_size = child_node.size.computed_size;

                    match self.frame_nodes[index].size.axis {
                        Axis::Horizontal => {
                            node_size[Axis::Horizontal as usize] +=
                                child_size[Axis::Horizontal as usize];
                        }
                        Axis::Vertical => {
                            if child_size[Axis::Horizontal as usize]
                                > node_size[Axis::Horizontal as usize]
                            {
                                node_size[Axis::Horizontal as usize] =
                                    child_size[Axis::Horizontal as usize];
                            }
                        }
                    }
                }

                self.frame_nodes[index].size.computed_size = node_size;
            }
        }

        if post_compute_vertical {
            self.frame_nodes[index].size.computed_size[Axis::Vertical as usize] = 0;

            if let Some(first_child_index) = self.node_ref(index).first {
                let mut node_size = self.frame_nodes[index].size.computed_size;
                for child_node in NodeIter::from_index(&self.frame_nodes, first_child_index, false)
                {
                    let child_size = child_node.size.computed_size;

                    match self.frame_nodes[index].size.axis {
                        Axis::Horizontal => {
                            if child_size[Axis::Vertical as usize]
                                > node_size[Axis::Vertical as usize]
                            {
                                node_size[Axis::Vertical as usize] =
                                    child_size[Axis::Vertical as usize];
                            }
                        }
                        Axis::Vertical => {
                            node_size[Axis::Vertical as usize] +=
                                child_size[Axis::Vertical as usize];
                        }
                    }
                }

                self.frame_nodes[index].size.computed_size = node_size;
            }
        }

        let iter = NodeIter::from_index(&self.frame_nodes, 0, true);

        for node in iter {
            let Some(persistent) = self.persistent.get_mut(&node.key) else {
                continue;
            };

            persistent.size = node.size;
        }
    }
}

struct PersistentIter<'a> {
    cx: &'a Context,
    node_iter: NodeIter<'a>,
}

impl<'a> PersistentIter<'a> {
    fn from_context(cx: &'a Context) -> Self {
        Self {
            cx,
            node_iter: NodeIter::from_index(&cx.frame_nodes, 0, true),
        }
    }
}

impl<'a> Iterator for PersistentIter<'a> {
    type Item = &'a PersistentNodeData;

    fn next(&mut self) -> Option<Self::Item> {
        self.node_iter
            .next()
            .and_then(|node| self.cx.persistent.get(&node.key))
    }
}

struct NodeIter<'a> {
    frame_nodes: &'a [FrameNode],
    index: NodeIndex,
    reached_end: bool,
    deep: bool,
}

impl<'a> NodeIter<'a> {
    fn from_index(frame_nodes: &'a [FrameNode], index: NodeIndex, deep: bool) -> Self {
        Self {
            frame_nodes,
            index,
            reached_end: false,
            deep,
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
            if self.deep {
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
            } else if let Some(next) = node.next {
                self.index = next;
            } else {
                self.reached_end = true;
            }

            return Some(node);
        }

        None
    }
}
