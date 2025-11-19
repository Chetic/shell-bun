/**
 * Interactive UI components using Ink
 */

const React = require('react');
const { Text, Box, useInput, useApp } = require('ink');

// Simple text display component (input is handled in Menu's useInput)
function TextInputDisplay({ value }) {
  return React.createElement(Text, null, value);
}

// Main Menu Component
function Menu({ menuItems, onSelect, onExecute, onDetails, onQuit }) {
  const [selectedIndex, setSelectedIndex] = React.useState(0);
  const [filter, setFilter] = React.useState('');
  const [selectedItems, setSelectedItems] = React.useState(new Set());
  const [showFilter, setShowFilter] = React.useState(false);
  const { exit } = useApp();

  // Filter menu items
  const filteredItems = React.useMemo(() => {
    if (!filter) return menuItems;
    const lowerFilter = filter.toLowerCase();
    return menuItems.filter(item => 
      item.label.toLowerCase().includes(lowerFilter)
    );
  }, [menuItems, filter]);

  // Handle keyboard input
  useInput((input, key) => {
    if (key.escape) {
      if (showFilter) {
        // Exit filter mode
        setShowFilter(false);
        setFilter('');
        return;
      }
      onQuit();
      exit();
      return;
    }

    if (showFilter) {
      // Filter mode - handle text input
      if (key.return) {
        setShowFilter(false);
        return;
      } else if (key.backspace || key.delete) {
        if (filter.length > 0) {
          setFilter(filter.slice(0, -1));
        }
        return;
      } else if (input && input.length === 1 && /[\x20-\x7E]/.test(input)) {
        // Printable ASCII characters
        setFilter(filter + input);
        return;
      }
      return;
    }

    // Navigation
    if (key.upArrow) {
      setSelectedIndex(prev => Math.max(0, prev - 1));
    } else if (key.downArrow) {
      setSelectedIndex(prev => Math.min(filteredItems.length - 1, prev + 1));
    } else if (key.pageUp) {
      setSelectedIndex(prev => Math.max(0, prev - 10));
    } else if (key.pageDown) {
      setSelectedIndex(prev => Math.min(filteredItems.length - 1, prev + 10));
    } else if (key.return) {
      // Enter - execute
      const item = filteredItems[selectedIndex];
      if (item) {
        if (item.type === 'details') {
          onDetails(item.app);
        } else if (selectedItems.size > 0) {
          onExecute(Array.from(selectedItems));
          setSelectedItems(new Set());
        } else {
          onExecute([`${item.app} - ${item.action}`]);
        }
      }
    } else if (input === ' ') {
      // Space - toggle selection
      const item = filteredItems[selectedIndex];
      if (item && item.type === 'action') {
        const key = `${item.app} - ${item.action}`;
        setSelectedItems(prev => {
          const next = new Set(prev);
          if (next.has(key)) {
            next.delete(key);
          } else {
            next.add(key);
          }
          return next;
        });
      }
    } else if (input === '+') {
      // Select all visible
      const visibleActions = filteredItems
        .filter(item => item.type === 'action')
        .map(item => `${item.app} - ${item.action}`);
      setSelectedItems(new Set(visibleActions));
    } else if (input === '-') {
      // Deselect all visible
      const visibleActions = filteredItems
        .filter(item => item.type === 'action')
        .map(item => `${item.app} - ${item.action}`);
      setSelectedItems(prev => {
        const next = new Set(prev);
        visibleActions.forEach(key => next.delete(key));
        return next;
      });
    } else if (key.backspace || key.delete) {
      // Clear filter
      if (filter) {
        setFilter('');
        setSelectedIndex(0);
      }
    } else if (input && input.length === 1 && /[a-zA-Z0-9]/.test(input)) {
      // Start filtering
      setShowFilter(true);
      setFilter(input);
      setSelectedIndex(0);
    }
  });

  // Update selected index when filter changes
  React.useEffect(() => {
    if (selectedIndex >= filteredItems.length) {
      setSelectedIndex(Math.max(0, filteredItems.length - 1));
    }
  }, [filteredItems.length, selectedIndex]);

  const displayItems = filteredItems.slice(
    Math.max(0, selectedIndex - 10),
    Math.min(filteredItems.length, selectedIndex + 20)
  );
  const displayStart = Math.max(0, selectedIndex - 10);

  // Build children for the main Box
  const children = [];
  
  // Help text
  children.push(
    React.createElement(Box, { key: 'help1' },
      React.createElement(Text, { bold: true, color: 'cyan' },
        'Navigation: ↑/↓ arrows | PgUp/PgDn: page | Type: filter | Space: select | Enter: execute | ESC: quit')
    )
  );
  
  children.push(
    React.createElement(Box, { key: 'help2' },
      React.createElement(Text, { bold: true, color: 'cyan' },
        'Shortcuts: \'+\' select visible | \'-\' deselect visible | Delete: clear filter')
    )
  );
  
  // Filter
  children.push(
    React.createElement(Box, { key: 'filter', marginTop: 1 },
      React.createElement(Text, { color: 'yellow' }, `Filter: ${showFilter ? filter : (filter || '(type to search)')}`),
      showFilter ? React.createElement(Text, null, '_') : null
    )
  );
  
  // Selected count
  children.push(
    React.createElement(Box, { key: 'selected', marginTop: 1 },
      React.createElement(Text, { color: selectedItems.size > 0 ? 'green' : 'gray' },
        `Selected: ${selectedItems.size} items`)
    )
  );
  
  // Menu items
  const menuChildren = [];
  if (displayStart > 0) {
    menuChildren.push(
      React.createElement(Text, { key: 'above', dimColor: true },
        `  ... ${displayStart} more item(s) above ...`)
    );
  }
  
  displayItems.forEach((item, idx) => {
    const actualIndex = displayStart + idx;
    const isSelected = actualIndex === selectedIndex;
    const itemKey = item.type === 'action' 
      ? `${item.app} - ${item.action}` 
      : item.label;
    const isChecked = selectedItems.has(itemKey);
    const isDetails = item.type === 'details';

    let prefix = '  ';
    if (isSelected) prefix = '► ';

    let color = 'white';
    if (isSelected && isChecked) {
      color = 'green';
    } else if (isSelected && isDetails) {
      color = 'magenta';
    } else if (isSelected) {
      color = 'cyan';
    } else if (isChecked) {
      color = 'green';
    } else if (isDetails) {
      color = 'yellow';
    }

    const suffix = isChecked ? ' [✓]' : '';

    menuChildren.push(
      React.createElement(Text, { key: actualIndex, color: color },
        `${prefix}${item.label}${suffix}`)
    );
  });
  
  if (displayStart + displayItems.length < filteredItems.length) {
    menuChildren.push(
      React.createElement(Text, { key: 'below', dimColor: true },
        `  ... ${filteredItems.length - (displayStart + displayItems.length)} more item(s) below ...`)
    );
  }
  
  children.push(
    React.createElement(Box, { key: 'menu', marginTop: 1, flexDirection: 'column' }, ...menuChildren)
  );

  return React.createElement(Box, { flexDirection: 'column' }, ...children);
}

module.exports = { Menu };
