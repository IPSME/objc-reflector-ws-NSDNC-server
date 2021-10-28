//
//  main.m
//  objc-nativews
//
//  Created by dev on 2021-10-18.
//  Copyright © 2021 Root Interface. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "msgenv_NSDNC.h"

#include <iostream>
#include <set>

NSUUID* g_uuid_ID= [NSUUID UUID];

// TODO: How do I fix the "address is in use" error when trying to restart my server?
// https://docs.websocketpp.org/faq.html

//----------------------------------------------------------------------------------------------------------------
#pragma mark ws -> me

// requires websocketpp header include
// requires asio-1.20.0 header include
#define ASIO_STANDALONE

// https://stackoverflow.com/questions/31755210/how-to-suppress-header-file-warnings-from-an-xcode-project
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include <websocketpp/config/asio_no_tls.hpp>
#include <websocketpp/server.hpp>
#pragma clang diagnostic pop

using websocketpp::connection_hdl;
using websocketpp::lib::placeholders::_1;
using websocketpp::lib::placeholders::_2;
using websocketpp::lib::bind;

// Create a server endpoint
typedef websocketpp::server<websocketpp::config::asio> ws_server;
ws_server g_ws_server;

typedef std::set<connection_hdl,std::owner_less<connection_hdl>> connection_list;
connection_list g_connection_list;


// pull out the type of messages sent by our config
typedef ws_server::message_ptr message_ptr;

// Define a callback to handle connect
void on_open(ws_server* server, websocketpp::connection_hdl hdl)
{
	std::cout << "on_open called with hdl: " << hdl.lock().get()	<< std::endl;
	g_connection_list.insert(hdl);
}

// Define a callback to handle disconnect
void on_close(ws_server* server, websocketpp::connection_hdl hdl)
{
	std::cout << "on_close called with hdl: " << hdl.lock().get()	<< std::endl;
	g_connection_list.erase(hdl);
}

// Define a callback to handle incoming messages
void on_message(ws_server* server, websocketpp::connection_hdl hdl, message_ptr msg)
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
	
	NSString* nsstr_msg= [NSString stringWithCString:str_msg.c_str() encoding:NSUTF8StringEncoding];

	//TODO: What encoding does nodejs use? should the code check for NSUTF16StringEncoding ?1
	
	NSLog(@"ws -> me: %@", nsstr_msg);
	
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:nsstr_msg object:g_uuid_ID.UUIDString userInfo:nil];
}

//----------------------------------------------------------------------------------------------------------------
#pragma mark ws <- me

void handler_(NSString* nsstr_msg, NSString* object)
{
	NSLog(@"handler_: %@", nsstr_msg);
	
	if (NULL != object)
	{
		if (YES == [object isEqualToString:g_uuid_ID.UUIDString]) {
			NSLog(@"DROPPED! ricochet: %@", nsstr_msg);
			return;
		}
	}
	
	//TODO: What encoding does objective-C use? should the code check for NSUTF16StringEncoding ?1
	
	NSLog(@"ws <- me: %@", nsstr_msg);
	
	std::string str_msg= [nsstr_msg cStringUsingEncoding:NSUTF8StringEncoding];
	
	try {
		websocketpp::lib::error_code ec;
		
		for (auto it : g_connection_list)
			g_ws_server.send(it, str_msg.c_str(), websocketpp::frame::opcode::TEXT, ec);
	}
	catch (websocketpp::exception const & e) {
		std::cout << "Echo failed because: " << "(" << e.what() << ")" << std::endl;
	}
}

//----------------------------------------------------------------------------------------------------------------
#pragma mark main()

int main(int argc, const char * argv[])
{
	@autoreleasepool
	{
		[MsgEnv_NSDNC subscribe:handler_];

		//-------------

		try {
			// Set logging settings
			g_ws_server.set_access_channels(websocketpp::log::alevel::all);
			g_ws_server.clear_access_channels(websocketpp::log::alevel::frame_payload);
			
			// Initialize Asio
			g_ws_server.init_asio();
			
			// Register our message handler
			g_ws_server.set_open_handler( bind(&on_open,&g_ws_server,::_1) );
			g_ws_server.set_close_handler( bind(&on_close,&g_ws_server,::_1) );
			g_ws_server.set_message_handler( bind(&on_message,&g_ws_server,::_1,::_2) );

			// Listen on port 8082
			g_ws_server.listen(8082);
			
			// Start the server accept loop
			g_ws_server.start_accept();

			NSLog(@"Running ...");
	
			while (true)
			{
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];

				// Start the ASIO io_service run loop
//				g_ws_server.run();
				g_ws_server.poll();
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
