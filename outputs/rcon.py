#!/usr/bin/env python3
# 简易 Minecraft RCON 客户端（仅用 Python 标准库，无需安装任何东西）
# 用法: python3 rcon.py 地址 端口 密码 "要执行的命令"
import socket
import struct
import sys


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("连接被关闭")
        buf += chunk
    return buf


def send_packet(sock, req_id, ptype, body):
    payload = struct.pack("<ii", req_id, ptype) + body.encode("utf-8") + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(payload)) + payload)


def read_packet(sock):
    length = struct.unpack("<i", recv_exact(sock, 4))[0]
    data = recv_exact(sock, length)
    req_id, ptype = struct.unpack("<ii", data[:8])
    body = data[8:-2].decode("utf-8", errors="replace")
    return req_id, ptype, body


def main():
    if len(sys.argv) != 5:
        print('用法: python3 rcon.py 地址 端口 密码 "命令"')
        print('示例: python3 rcon.py 127.0.0.1 25575 密码 "op sqtiamo"')
        sys.exit(1)

    host, port, password, command = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]

    sock = socket.create_connection((host, port), timeout=10)

    # 认证 (type 3)
    send_packet(sock, 1, 3, password)
    req_id, ptype, body = read_packet(sock)
    if req_id == -1:
        print("RCON 密码错误")
        sys.exit(1)

    # 执行命令 (type 2)
    send_packet(sock, 2, 2, command)
    req_id, ptype, body = read_packet(sock)
    print(body)

    sock.close()


if __name__ == "__main__":
    main()
