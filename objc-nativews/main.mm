//
//  main.m
//  objc-nativews
//
//  Created by dev on 2021-10-18.
//  Copyright © 2021 Root Interface. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <iostream>

//----------------------------------------------------------------------------------------------------------------
#pragma mark websocketpp

// requires websocketpp header include
// requires boost-1.76 header include

// https://stackoverflow.com/questions/31755210/how-to-suppress-header-file-warnings-from-an-xcode-project
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include <websocketpp/config/asio_no_tls.hpp>
#include <websocketpp/server.hpp>
#pragma clang diagnostic pop

typedef websocketpp::server<websocketpp::config::asio> server;

using websocketpp::lib::placeholders::_1;
using websocketpp::lib::placeholders::_2;
using websocketpp::lib::bind;

// pull out the type of messages sent by our config
typedef server::message_ptr message_ptr;

// Define a callback to handle incoming messages
void on_message(server* s, websocketpp::connection_hdl hdl, message_ptr msg) {
	std::cout << "on_message called with hdl: " << hdl.lock().get()
	<< " and message: " << msg->get_payload()
	<< std::endl;
	
	// check for a special command to instruct the server to stop listening so
	// it can be cleanly exited.
	if (msg->get_payload() == "stop-listening") {
		s->stop_listening();
		return;
	}
	
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"UEENotification" object:nil userInfo:nil];

	
	try {
		s->send(hdl, msg->get_payload(), msg->get_opcode());
	}
	catch (websocketpp::exception const & e) {
		std::cout << "Echo failed because: "
		<< "(" << e.what() << ")" << std::endl;
	}
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

- (void) recvd:(NSNotification *)notification
{
	NSLog(@"recvd:(NSNotification *)notification");
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

		// Create a server endpoint
		server echo_server;
		
		try {
			// Set logging settings
			echo_server.set_access_channels(websocketpp::log::alevel::all);
			echo_server.clear_access_channels(websocketpp::log::alevel::frame_payload);
			
			// Initialize Asio
			echo_server.init_asio();
			
			// Register our message handler
			echo_server.set_message_handler(bind(&on_message,&echo_server,::_1,::_2));
			
			// Listen on port 8082
			echo_server.listen(8082);
			
			// Start the server accept loop
			echo_server.start_accept();

			NSLog(@"Running ...");
	
			while (true)
			{
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];

				// Start the ASIO io_service run loop
//				echo_server.run();
				echo_server.poll();
				
//				NSLog(@".");
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
