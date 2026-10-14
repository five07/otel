module main

import net.http
import os
import time

// Collector counts the OTLP requests it gets.
@[heap]
struct Collector {
mut:
	bodies shared []string
}

fn (mut c Collector) handle(req http.Request) http.Response {
	lock c.bodies {
		c.bodies << req.data
	}
	return http.new_response(body: '{}')
}

fn test_the_quickstart_delivers_its_spans() {
	c := &Collector{}
	mut server := &http.Server{
		addr:                 '127.0.0.1:0'
		handler:              c
		show_startup_message: false
		accept_timeout:       50 * time.millisecond
	}
	spawn fn (mut s http.Server) {
		s.listen_and_serve()
	}(mut server)
	server.wait_till_running()!
	os.setenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://${server.addr}', true)
	defer {
		os.unsetenv('OTEL_EXPORTER_OTLP_ENDPOINT')
		server.stop()
	}
	quickstart()!
	bodies := rlock c.bodies {
		c.bodies.clone()
	}
	assert bodies.len == 1
	assert bodies[0].contains('"name":"checkout"')
	assert bodies[0].contains('"name":"charge"')
}
