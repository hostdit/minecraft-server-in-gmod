#define GMMODULE
#include "GarrysMod/Lua/Interface.h"
#ifdef _WIN32
	#include <winsock2.h>
	#include <ws2tcpip.h>
	#include <process.h>
	#pragma comment(lib, "ws2_32.lib")
	typedef SOCKET sock_t;
	typedef int socklen_t;
	#define BADSOCK INVALID_SOCKET
	#define lastError() WSAGetLastError()
	#define WOULDBLOCK(e) ((e) == WSAEWOULDBLOCK)
	#define closeSock(s) closesocket(s)
	#define ownPid() ((int)_getpid())
#else
	#include <sys/socket.h>
	#include <netinet/in.h>
	#include <netinet/tcp.h>
	#include <arpa/inet.h>
	#include <unistd.h>
	#include <fcntl.h>
	#include <errno.h>
	typedef int sock_t;
	#define BADSOCK (-1)
	#define lastError() errno
	#define WOULDBLOCK(e) ((e) == EAGAIN || (e) == EWOULDBLOCK)
	#define closeSock(s) close(s)
	#define ownPid() ((int)getpid())
#endif
#include <string.h>
#include <stdio.h>
#include <string>
#include <map>
#include <mutex>
#include <thread>
#include <atomic>
#include <chrono>

using namespace GarrysMod::Lua;

struct Conn
{
	std::string out;
	size_t off = 0;
	bool play = false;
	bool broken = false;
	std::string beat;
	double beatEvery = 2.0;
	std::chrono::steady_clock::time_point lastBeat = std::chrono::steady_clock::now();
};

static sock_t listenFd = BADSOCK;
static std::map<sock_t, Conn> conns;
static std::mutex lock;
static std::thread worker;
static std::atomic<bool> running(false);

static const char* errText(int err)
{
	static thread_local char buf[256];
#ifdef _WIN32
	buf[0] = 0;
	FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)err, 0, buf, sizeof(buf), NULL);
	if (buf[0] == 0) snprintf(buf, sizeof(buf), "winsock error %d", err);
	for (char* p = buf; *p; ++p) if (*p == '\r' || *p == '\n') *p = ' ';
#else
	snprintf(buf, sizeof(buf), "%s", strerror(err));
#endif
	return buf;
}

static bool setNonBlocking(sock_t fd)
{
#ifdef _WIN32
	u_long on = 1;
	return ioctlsocket(fd, FIONBIO, &on) == 0;
#else
	int flags = fcntl(fd, F_GETFL, 0);
	return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
#endif
}

static void pumpConn(sock_t fd, Conn& c)
{
	auto now = std::chrono::steady_clock::now();
	if (c.play && !c.beat.empty() && c.off >= c.out.size())
	{
		double since = std::chrono::duration<double>(now - c.lastBeat).count();
		if (since >= c.beatEvery)
		{
			c.out.erase(0, c.off);
			c.off = 0;
			c.out += c.beat;
			c.lastBeat = now;
		}
	}
	while (c.off < c.out.size())
	{
		int n = (int)send(fd, c.out.data() + c.off, (int)(c.out.size() - c.off), 0);
		if (n > 0) { c.off += (size_t)n; continue; }
		if (n < 0 && WOULDBLOCK(lastError())) break;
		c.broken = true;
		break;
	}
	if (c.off > 0 && c.off >= c.out.size()) { c.out.clear(); c.off = 0; }
	else if (c.off > 65536) { c.out.erase(0, c.off); c.off = 0; }
}

static void workerLoop()
{
	while (running.load())
	{
		{
			std::lock_guard<std::mutex> g(lock);
			for (auto& kv : conns) if (!kv.second.broken) pumpConn(kv.first, kv.second);
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
	}
}

static void startWorker()
{
	if (running.load()) return;
	running.store(true);
	worker = std::thread(workerLoop);
}

static void stopWorker()
{
	if (!running.load()) return;
	running.store(false);
	if (worker.joinable()) worker.join();
}

static void closeEverything()
{
	stopWorker();
	std::lock_guard<std::mutex> g(lock);
	for (auto& kv : conns) closeSock(kv.first);
	conns.clear();
	if (listenFd != BADSOCK) { closeSock(listenFd); listenFd = BADSOCK; }
}

LUA_FUNCTION_STATIC(mcListen)
{
	int port = (int)LUA->CheckNumber(1);
	closeEverything();
	sock_t fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd == BADSOCK) LUA->ThrowError(errText(lastError()));
	int one = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (const char*)&one, sizeof(one));
	sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	addr.sin_port = htons((unsigned short)port);
	if (bind(fd, (sockaddr*)&addr, sizeof(addr)) != 0 || listen(fd, 8) != 0 || !setNonBlocking(fd))
	{
		int err = lastError();
		closeSock(fd);
		LUA->ThrowError(errText(err));
	}
	listenFd = fd;
	startWorker();
	LUA->PushBool(true);
	return 1;
}

LUA_FUNCTION_STATIC(mcAccept)
{
	if (listenFd == BADSOCK) LUA->ThrowError("not listening");
	sockaddr_in addr;
	socklen_t len = sizeof(addr);
	sock_t fd = accept(listenFd, (sockaddr*)&addr, &len);
	if (fd == BADSOCK)
	{
		int err = lastError();
		if (WOULDBLOCK(err)) { LUA->PushNil(); return 1; }
		LUA->ThrowError(errText(err));
	}
	if (!setNonBlocking(fd)) { closeSock(fd); LUA->ThrowError("could not set non-blocking"); }
	int one = 1;
	setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (const char*)&one, sizeof(one));
	char ip[INET_ADDRSTRLEN] = "?";
	inet_ntop(AF_INET, &addr.sin_addr, ip, sizeof(ip));
	{
		std::lock_guard<std::mutex> g(lock);
		conns[fd] = Conn();
	}
	LUA->PushNumber((double)fd);
	LUA->PushString(ip);
	return 2;
}

LUA_FUNCTION_STATIC(mcRecv)
{
	sock_t fd = (sock_t)LUA->CheckNumber(1);
	{
		std::lock_guard<std::mutex> g(lock);
		auto it = conns.find(fd);
		if (it == conns.end() || it->second.broken) { LUA->PushNil(); return 1; }
	}
	char buf[65536];
	int n = (int)recv(fd, buf, sizeof(buf), 0);
	if (n > 0) { LUA->PushString(buf, (unsigned int)n); return 1; }
	if (n == 0) { LUA->PushNil(); return 1; }
	if (WOULDBLOCK(lastError())) { LUA->PushString("", 0); return 1; }
	LUA->PushNil();
	return 1;
}

LUA_FUNCTION_STATIC(mcQueue)
{
	sock_t fd = (sock_t)LUA->CheckNumber(1);
	unsigned int len = 0;
	const char* data = LUA->GetString(2, &len);
	std::lock_guard<std::mutex> g(lock);
	auto it = conns.find(fd);
	if (it == conns.end() || it->second.broken) { LUA->PushBool(false); return 1; }
	it->second.out.append(data, len);
	LUA->PushBool(true);
	return 1;
}

LUA_FUNCTION_STATIC(mcPlay)
{
	sock_t fd = (sock_t)LUA->CheckNumber(1);
	unsigned int len = 0;
	const char* data = LUA->GetString(2, &len);
	double every = LUA->CheckNumber(3);
	std::lock_guard<std::mutex> g(lock);
	auto it = conns.find(fd);
	if (it == conns.end()) return 0;
	it->second.play = true;
	it->second.beat.assign(data, len);
	it->second.beatEvery = every;
	it->second.lastBeat = std::chrono::steady_clock::now();
	return 0;
}

LUA_FUNCTION_STATIC(mcPending)
{
	sock_t fd = (sock_t)LUA->CheckNumber(1);
	std::lock_guard<std::mutex> g(lock);
	auto it = conns.find(fd);
	if (it == conns.end()) { LUA->PushNumber(-1); LUA->PushBool(true); return 2; }
	LUA->PushNumber((double)(it->second.out.size() - it->second.off));
	LUA->PushBool(it->second.broken);
	return 2;
}

LUA_FUNCTION_STATIC(mcClose)
{
	sock_t fd = (sock_t)LUA->CheckNumber(1);
	std::lock_guard<std::mutex> g(lock);
	conns.erase(fd);
	closeSock(fd);
	return 0;
}

LUA_FUNCTION_STATIC(mcStop)
{
	closeEverything();
	return 0;
}

LUA_FUNCTION_STATIC(mcCount)
{
	std::lock_guard<std::mutex> g(lock);
	LUA->PushNumber((double)conns.size());
	return 1;
}

LUA_FUNCTION_STATIC(mcInfo)
{
	LUA->PushNumber((double)listenFd);
	if (listenFd == BADSOCK) { LUA->PushNumber(-1); LUA->PushString("no listen socket"); return 3; }
	sockaddr_in addr;
	socklen_t len = sizeof(addr);
	if (getsockname(listenFd, (sockaddr*)&addr, &len) != 0)
	{
		LUA->PushNumber(-1);
		LUA->PushString(errText(lastError()));
		return 3;
	}
	LUA->PushNumber((double)ntohs(addr.sin_port));
	LUA->PushString(running.load() ? "ok, heartbeat thread up" : "ok, no thread");
	return 3;
}

LUA_FUNCTION_STATIC(mcPid)
{
	LUA->PushNumber((double)ownPid());
	return 1;
}

GMOD_MODULE_OPEN()
{
#ifdef _WIN32
	WSADATA wsa;
	WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
	LUA->PushSpecial(SPECIAL_GLOB);
	LUA->CreateTable();
	LUA->PushCFunction(mcListen);  LUA->SetField(-2, "listen");
	LUA->PushCFunction(mcAccept);  LUA->SetField(-2, "accept");
	LUA->PushCFunction(mcRecv);    LUA->SetField(-2, "recv");
	LUA->PushCFunction(mcQueue);   LUA->SetField(-2, "queue");
	LUA->PushCFunction(mcPlay);    LUA->SetField(-2, "play");
	LUA->PushCFunction(mcPending); LUA->SetField(-2, "pending");
	LUA->PushCFunction(mcClose);   LUA->SetField(-2, "close");
	LUA->PushCFunction(mcStop);    LUA->SetField(-2, "stop");
	LUA->PushCFunction(mcCount);   LUA->SetField(-2, "count");
	LUA->PushCFunction(mcInfo);    LUA->SetField(-2, "info");
	LUA->PushCFunction(mcPid);     LUA->SetField(-2, "pid");
	LUA->SetField(-2, "mcsock");
	LUA->Pop();
	return 0;
}

GMOD_MODULE_CLOSE()
{
	closeEverything();
#ifdef _WIN32
	WSACleanup();
#endif
	return 0;
}
