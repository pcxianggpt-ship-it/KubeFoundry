#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import argparse

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from kubefoundry.store.db import get_db_path, init_db


def parse_args(argv):
    parser = argparse.ArgumentParser(description="KubeFoundry Web Wizard backend")
    parser.add_argument("--host", default=os.environ.get("KF_WEB_HOST", "0.0.0.0"))
    parser.add_argument("--port", default=int(os.environ.get("KF_WEB_PORT", "5000")), type=int)
    parser.add_argument(
        "--debug",
        action="store_true",
        default=os.environ.get("KF_WEB_DEBUG", "false").lower() == "true",
    )
    parser.add_argument("--init-db", action="store_true", help="初始化 SQLite 数据库后退出")
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    if args.init_db:
        init_db()
        print("SQLite 数据库已初始化: %s" % get_db_path())
        return 0

    from kubefoundry.api.routes import create_app

    app = create_app()
    app.run(host=args.host, port=args.port, debug=args.debug, threaded=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
