I have some clients on a network not routed to the internet (with IPv4 RFC1918-addresses) that should be allowed to communicate with a SCAIP/SIP server (Skyresponse - scaips://prod2.voip.skyresponse.com:5061).

* An idea is to have a SIP proxy standing on a server that is attached both to the isolated networ and to internet, which may receive the SIP traffic and forward it on to the endpoint.  Is this feasable?
* Does there exist any working software out there that can be used as-is or as a starting point?  Please do a review of the projects at https://siproxd.sourceforge.io/ and https://www.kamailio.org/w/ and consider if there are any other open source software that can be used for this purpose.
* If no existing software can be used, make design documents for a new service.
  * Keep in mind that it's more to it than just forwarding IP packages, the content of the packages will need to be rewritten as well.
  * We need integration tests that can be run from anywhere, even from an offline developer local laptop.  Possibly having a test server and a test client as docker containers.
  * Python is the preferred programming language, but consider if any other programming languages are more optimized for this task
  * This software should run in very sharp production.
    * It's important with a stable service covering all kind of corner cases
	* It's important to have metrics, readiness probe and health probe that can be monitored.
