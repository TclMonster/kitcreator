#
# This script is designed to be called by jobs in .github/workflows/create-release.yml
#

package require http
package require tls
package require json
package require json::write
package require tcl::chan::string

http::register https 443 [list ::tls::socket -autoservername true -require true]

if {! [info exists env(GH_TOKEN)]} {
    puts stderr "\"env.GH_TOKEN\" must be set to \"secrets.GITHUB_TOKEN\""
    exit 1
}

if {[llength $argv] < 4} {
    puts stderr "Usage: create-release.tcl api_url owner repo tag_name"
    exit 1
}

lassign $argv api_url owner repo tag_name

set release_url $api_url/repos/$owner/$repo/releases
set headers [list Accept application/vnd.github+json Authorization "Bearer $env(GH_TOKEN)" X-GitHub-Api-Version 2022-11-28]
set req_data [::tcl::chan::string [::json::write object-strings tag_name $tag_name]]
set response [http::geturl $release_url -type application/json -querychannel $req_data -headers $headers]
if {[http::status $response] != "ok"} {
    puts stderr "Error retrieving URL \"$release_url\""
    http::cleanup $response
    exit 1
}

if {[http::ncode $response] != 201} {
    puts stderr "Failed to create release"
    puts stderr [http::data $response]
    exit 1
}

set upload_url [string map [list \{?name,label\} {}] \
                    [dict get [::json::json2dict [http::data $response]] upload_url]]

foreach kitfile [glob kitcreator-*-kits/*] {
    puts -nonewline "Uploading \"$kitfile\"... "
    set query [http::formatQuery name [file tail $kitfile]]
    set kitchan  [open $kitfile]
    fconfigure $kitchan -translation binary
    set response [http::geturl $upload_url -query $query -querychannel $kitchan -type application/octet-stream -headers $headers]
    if {[http::status $response] != "ok" || [http::ncode $response] != 201} {
        puts "Failed!"
        puts stderr [http::data $response]
        exit 1
    }
    puts "Success."
    close $kitchan
    http::cleanup $response
}
