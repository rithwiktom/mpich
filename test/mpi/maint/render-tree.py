import json
import sys
import argparse

try:
    from graphviz import Digraph
except ImportError as e:
    sys.exit('Unable to import graphviz module: {}.\n'.format(e) +
             'Please install the graphviz module by running the following command:\n'
             '\n'
             '      python -m pip install graphviz\n')


def main():
    args = parse_args()
    input_tree = load_tree(args.node_files)
    render_tree(input_tree, args.format)


def load_tree(node_files):
    result = []
    for filename in node_files:
        with open(filename) as the_file:
            result.append(json.load(the_file))
    return result


def render_tree(input_tree, format):
    dot = Digraph('Tree')
    for node in input_tree:
        dot.node(str(node['rank']))
    for node in input_tree:
        dot.edges([[str(node["rank"]), str(child)] for child in node['children']])
    dot.render(format=format, view=True)


def parse_args():
    description = 'Render a topology-aware collective tree as a graphical tree.'
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('node_files', metavar='FILE', nargs='+', help='File(s) containing the JSON-formatted tree nodes to be rendered (e.g. tree-node-*.json).')
    parser.add_argument('--format', '-f', default='svg', help='Output format. Can be any format supported by graphviz. Default: svg.')
    return parser.parse_args()


if __name__ == '__main__':
    main()
