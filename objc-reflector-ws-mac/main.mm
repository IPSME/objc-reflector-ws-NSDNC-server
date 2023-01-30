//
//  main.m
//  objc-nativews
//
//  Created by dev on 2021-10-18.
//  Copyright © 2021 Root Interface. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IPSME_MsgEnv.h"

#include <iostream>
#include <set>
#include "msg_cache-dedup.h"

typedef duplicate t_duplicate;
t_duplicate g_duplicate;

//----------------------------------------------------------------------------------------------------------------
#pragma mark ws -> nsdnc

// requires websocketpp header include
// requires asio-1.20.0 header include
#define ASIO_STANDALONE

// https://stackoverflow.com/questions/31755210/how-to-suppress-header-file-warnings-from-an-xcode-project
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include <websocketpp/config/asio_no_tls.hpp>
#include <websocketpp/server.hpp>
#pragma clang diagnostic pop

typedef websocketpp::connection_hdl t_connection_hdl;
//using websocketpp::connection_hdl;
using websocketpp::lib::placeholders::_1;
using websocketpp::lib::placeholders::_2;
using websocketpp::lib::bind;

// Create a server endpoint
typedef websocketpp::server<websocketpp::config::asio> t_ws_server;
t_ws_server g_ws_server_;

typedef std::set<t_connection_hdl,std::owner_less<t_connection_hdl>> t_connection_list;
t_connection_list g_connection_list;

// pull out the type of messages sent by our config
typedef t_ws_server::message_ptr t_message_ptr;

// Define a callback to handle connect
void on_open(t_ws_server* server, t_connection_hdl hdl)
{
	std::cout << "on_open called with hdl: " << hdl.lock().get()	<< std::endl;
	g_connection_list.insert(hdl);
}

// Define a callback to handle disconnect
void on_close(t_ws_server* server, t_connection_hdl hdl)
{
	std::cout << "on_close called with hdl: " << hdl.lock().get()	<< std::endl;
	g_connection_list.erase(hdl);
}

// Define a callback to handle incoming messages
void on_message(t_ws_server* server, t_connection_hdl hdl, t_message_ptr msg)
{
	//	std::cout << "on_message called with hdl: " << hdl.lock().get()
	//	<< " and message: " << msg->get_payload()
	//	<< std::endl;
	
	/*
	// check for a special command to instruct the server to stop listening so
	// it can be cleanly exited.
	if (msg->get_payload() == "stop-listening") {
		ws_server->stop_listening();
		return;
	}
	*/
	
	// https://www.cplusplus.com/reference/string/string/
	// Note that this class handles bytes independently of the encoding used:
	// If used to handle sequences of multi-byte or variable-length characters (such as UTF-8),
	// all members of this class (such as length or size), as well as its iterators,
	// will still operate in terms of bytes (not actual encoded characters).
	std::string str_msg= msg->get_payload();
	
	if (true == g_duplicate.exists(str_msg)) {
		// NSLog(@"on_message(message_ptr): ws ->| *DUP -- [%s]", str_msg.c_str());
		return;
	}
	
	NSString* nsstr_msg= [NSString stringWithCString:str_msg.c_str() encoding:NSUTF8StringEncoding];

	//TODO: What encoding does nodejs use? should the code check for NSUTF16StringEncoding ?1
	
	NSLog(@"on_message(message_ptr): ws -> nsdnc -- [%@]", nsstr_msg);
	
	// [IPSME_MsgEnv publish:nsstr_msg withObject:g_uuid_ID.UUIDString];
	[IPSME_MsgEnv publish:nsstr_msg];
}

//----------------------------------------------------------------------------------------------------------------
#pragma mark ws <- nsdnc

bool handler_NSString_(id id_msg, NSString* nsstr_msg)
{
	// NSLog(@"handler_NSString_: %@", nsstr_msg);
	
	// one way doors are only present when publishing messages out to clients
	//	if ((NULL != object) && (YES == [object isEqualToString:g_uuid_ID.UUIDString]) ) {
	//		NSLog(@"handler_NSString: *DUP |<- nsdnc -- [%@]", nsstr_msg);
	//		return false;
	//	}
	
	//TODO: What encoding does objective-C use? should the code check for NSUTF16StringEncoding ?1
	
	std::string str_msg= [nsstr_msg cStringUsingEncoding:NSUTF8StringEncoding];
	
	g_duplicate.cache(str_msg, t_entry_context(30s));
	
	NSLog(@"handler_NSString_: ws <- nsdnc -- [%@]", nsstr_msg);

	try {
		websocketpp::lib::error_code ec;
		
		for (auto it : g_connection_list)
			g_ws_server_.send(it, str_msg.c_str(), websocketpp::frame::opcode::TEXT, ec);
		
		return true;
	}
	catch (websocketpp::exception const & e) {
		std::cout << "handler_NSString_: Echo failed because: " << "(" << e.what() << ")" << std::endl;

		return false;
	}
}

void handler_(id id_msg, NSString* object)
{
	@try {
		if ([id_msg isKindOfClass:[NSString class]] && handler_NSString_(id_msg, id_msg))
			return;
	}
	@catch (id ue) {
		if ([ue isKindOfClass:[NSException class]]) {
			NSException* e= ue;
			NSLog(@"ERR: error is message execution: %@", [e reason]);
		}
		else
			NSLog(@"ERR: error is message execution");
		
		return;
	}
	
	// drop silently ...
	NSLog(@"handler_: DROP! %@", [id_msg class]);
}

//----------------------------------------------------------------------------------------------------------------
#pragma mark main()

bool gb_quit_= false;

void handler_sigint_(int s)
{
	printf("\nCaught SIG[%d]\n", s);

	// if the user presses ^C twice, then just exit.
	if (gb_quit_)
		exit(s);
	
	gb_quit_= true;

	// TODO: How do I fix the "address is in use" error when trying to restart my server? SO_REUSEADDR?
	// https://docs.websocketpp.org/faq.html | How do I cleanly exit an Asio transport based program
	// https://groups.google.com/g/websocketpp/c/rvBcIJ940Bc
	// 		An easy fix for this is to separate the socket from the connection object.
	//		In doing so you can maintain a concrete instance of the socket defer creation of the connection
	//		until the handle_accept is executed. At which time you can pass the socket of to the new connection.
	//		What this allows you to do then is explicitly close the socket when stop_listening() is called
	//		along with telling the acceptor to close.
	
	g_ws_server_.stop_listening();
	for (auto it : g_connection_list) {
		try {
			// https://github.com/zaphoyd/websocketpp/issues/545
			// needed ?
			// g_ws_server_.pause_reading(it);

			g_ws_server_.close(it, websocketpp::close::status::normal, "");
		}
		catch (websocketpp::lib::error_code ec) {
			std::cout << "lib::error_code " << ec << std::endl;
		}
	}
	
	// we don't have to stop it manually, it will stop when we stop listening
	// g_ws_server_.stop();

	// don't force an exit here, wait for a proper exit from the run loop; io_service.stopped()
	// exit(s);
}

int main(int argc, const char * argv[])
{
	// -----
	// https://stackoverflow.com/questions/1641182/how-can-i-catch-a-ctrl-c-event
	struct sigaction sa;

	sa.sa_handler = handler_sigint_;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = 0;

	sigaction(SIGINT, &sa, NULL);
	
	// -----
	
	@autoreleasepool
	{
		[IPSME_MsgEnv subscribe:handler_];

		//-------------

		int i_port= 8082;
		
		try {
			// Set logging settings
			g_ws_server_.set_access_channels(websocketpp::log::alevel::none);
			g_ws_server_.clear_access_channels(websocketpp::log::alevel::frame_payload);
			
			// Initialize Asio
			g_ws_server_.init_asio();
			
			// Register our message handler
			g_ws_server_.set_open_handler( bind(&on_open,&g_ws_server_,::_1) );
			g_ws_server_.set_close_handler( bind(&on_close,&g_ws_server_,::_1) );
			g_ws_server_.set_message_handler( bind(&on_message,&g_ws_server_,::_1,::_2) );

			// Listen on port 8082
			g_ws_server_.listen(i_port);
			
			// Start the server accept loop
			g_ws_server_.start_accept();

			NSLog(@"Running on [%d] ...", i_port);
	
			while (!gb_quit_ && !g_ws_server_.stopped())
			{
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];

				// g_ws_server_.run(); // start the ASIO io_service run loop
				g_ws_server_.poll();
			}
		}
		catch (websocketpp::exception const & e) {
			std::cout << e.what() << std::endl;
		}
		catch (...) {
			std::cout << "other exception" << std::endl;
		}

		NSLog(@"Exit!");
	}
	
	return 0;
}
