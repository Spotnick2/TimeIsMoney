"""Parse verified HTML into developer-local DOM inputs; never executes scripts."""
import json
import sys
from html.parser import HTMLParser

VOID = set("area base br col embed hr img input link meta param source track wbr".split())


class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = {"tag": "#document", "attrs": {}, "children": []}
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        # Optional end tags exercised by the reference's paragraph/option markup.
        if tag in ("option", "p", "li") and self.stack[-1]["tag"] == tag:
            self.stack.pop()
        node = {"tag": tag, "attrs": dict(attrs), "children": []}
        self.stack[-1]["children"].append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for i in range(len(self.stack)-1, 0, -1):
            if self.stack[i]["tag"] == tag:
                self.stack = self.stack[:i]
                break

    def handle_data(self, data):
        self.stack[-1]["children"].append({"text": data})


if __name__ == "__main__":
    parser = Tree()
    with open(sys.argv[1], encoding="utf-8", newline="") as file:
        parser.feed(file.read())
    print(json.dumps(parser.root, ensure_ascii=True))
