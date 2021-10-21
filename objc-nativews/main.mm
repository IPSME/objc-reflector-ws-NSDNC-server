//
//  main.m
//  objc-nativews
//
//  Created by dev on 2021-10-18.
//  Copyright © 2021 Root Interface. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <iostream>
#include <set>

// TODO: How do I fix the "address is in use" error when trying to restart my server?
// https://docs.websocketpp.org/faq.html

//----------------------------------------------------------------------------------------------------------------
#pragma mark websocketpp

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
	
	NSError* err= nil;
	NSDictionary *jsonDict= [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:str_msg.c_str() length:str_msg.length()]
															options:0
															  error:&err];

	// NSLog(@"%@", [jsonDict allKeys]);
	if (!jsonDict) {
		NSLog(@"DROP! ws_msg[%lu] isn't JSON.", str_msg.length());
		return;
	}
		
	NSString* nsstr_msg= [NSString stringWithCString:str_msg.c_str() encoding:NSUTF8StringEncoding];

	//TODO: What encoding does nodejs use? should the code check for NSUTF16StringEncoding ?1
	
	NSLog(@"ws -> me: %@", nsstr_msg);
	
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"UEENotification" object:nsstr_msg userInfo:nil];
}

//----------------------------------------------------------------------------------------------------------------
#pragma mark Singleton

@interface Singleton : NSObject {
//	NSString *someProperty;
}
//@property (nonatomic, retain) NSString *someProperty;

+ (id) getSharedInstance;
- (void) nop;
@end

//-------------

@implementation Singleton
//@synthesize someProperty;

+ (id) getSharedInstance
{
	static Singleton *_sharedInstance= nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_sharedInstance= [[self alloc] init];
	});

	return _sharedInstance;
}

- (id) init {
	if (self = [super init])
	{
		[[NSDistributedNotificationCenter defaultCenter] addObserver:self
															selector:@selector(recvd:)
																name:@"UEENotification"
															  object:nil];
	}
	return self;
}

- (void) dealloc {
	// Should never be called, but just here for clarity really.
}

- (void) nop
{
}

- (void) recvd:(NSNotification *)nfy
{
	NSAssert(NSOrderedSame == [nfy.name compare:@"UEENotification"], @"Are we only listening for UEENotifications or not?");
	
	//TODO: What encoding does objective-C use? should the code check for NSUTF16StringEncoding ?1

	//TOOD: drop your own sent messages
	
	NSError* err= nil;
	NSDictionary *jsonDict= [NSJSONSerialization JSONObjectWithData:[nfy.object dataUsingEncoding:NSUTF8StringEncoding]
														    options:0
															  error:&err];
	
	if (![nfy.object isKindOfClass:[NSString class]]) {
		NSLog(@"DROP! notification.object isn't a NSString.");
		return;
	}
	
	// NSLog(@"%@", [jsonDict allKeys]);
	if (!jsonDict) {
		NSLog(@"DROP! notification.object[%lu] isn't JSON.", (unsigned long)((NSString*)nfy.object).length);
		return;
	}
	
	NSLog(@"ws <- me: %@", nfy.object);

	std::string str_nfy_obj= [(NSString*)nfy.object cStringUsingEncoding:NSUTF8StringEncoding];
	
	try {
		websocketpp::lib::error_code ec;

		for (auto it : g_connection_list)
			g_ws_server.send(it, str_nfy_obj.c_str(), websocketpp::frame::opcode::TEXT, ec);
	}
	catch (websocketpp::exception const & e) {
		std::cout << "Echo failed because: " << "(" << e.what() << ")" << std::endl;
	}
}

@end

//----------------------------------------------------------------------------------------------------------------
#pragma mark main()

int main(int argc, const char * argv[])
{
	@autoreleasepool
	{
		NSLog(@"Hello, World!");
		
		Singleton* _singleton= [Singleton getSharedInstance];
		[_singleton nop];
		
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
