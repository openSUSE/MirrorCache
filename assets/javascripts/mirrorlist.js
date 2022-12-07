// jshint multistr: true
// jshint esversion: 6

var mirrors_country = [];
var mirrors_region  = [];
var mirrors_rest    = [];
var mapObject = [{}, {}, {}, {}];
var mapAlias  = ["map1","map2","map3","mapAll"];
var mapScale  = [ 4, 3, 1, 1];
var mapCenter = [ 1, 1, 0, 0 ];

function handleMirrorlistAjaxError(request, code, error, element) {
    if (request.responseJSON != undefined && request.responseJSON.error) {
        error += ': ' + request.responseJSON.error;
    } else if (request.responseText != undefined && request.responseText) {
        error += ': ' + request.responseText.error;
    }

    if (element) {
        element.innerText = 'Error: ' + error;
    }
}

function loadMirrorlist(url, country, region, element1, element2, element3) {
    $.ajax({
        url: url,
        method: 'GET',
        data:{ COUNTRY: country, REGION: region },
        success: function(response) {
            var l1 = response.l1;
            for(var i = 0; i < l1.length; i++) {
                var obj = l1[i];
                if (!obj) {
                    continue;
                }
                var a = document.createElement("a");
                var span = document.createElement("span");
                span.innerHTML = " (" + obj.location + ")";
                var ul = document.getElementById(element1);
                var li = document.createElement("li");
                a.textContent = obj.hostname;
                a.setAttribute('href', obj.url);
                li.appendChild(a);
                li.appendChild(span);
                ul.appendChild(li);
                mirrors_country.push({
                    url:obj.url,
                    hostname:obj.hostname,
                    country:obj.location,
                    lat:obj.lat,
                    lng:obj.lng,
                });
                document.getElementById("h51").innerText = mirrors_country.length;
            }
            var ulh = document.getElementById(element1.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }

            var l2 = response.l2;
            for(var i = 0; i < l2.length; i++) {
                var obj = l2[i];
                if (!obj) {
                    continue;
                }
                var a = document.createElement("a");
                var span = document.createElement("span");
                span.innerHTML = " (" + obj.location + ")";
                var ul = document.getElementById(element2);
                var li = document.createElement("li");
                a.textContent = obj.hostname;
                a.setAttribute('href', obj.url);
                li.appendChild(a);
                li.appendChild(span);
                ul.appendChild(li);
                mirrors_region.push({
                    url:obj.url,
                    hostname:obj.hostname,
                    country:obj.location,
                    lat:obj.lat,
                    lng:obj.lng,
                });
                document.getElementById("h52").innerText = mirrors_region.length;
            }
            ulh = document.getElementById(element2.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }

            var l3 = response.l3;
            for(var i = 0; i < l3.length; i++) {
                var obj = l3[i];
                if (!obj) {
                    continue;
                }
                var a = document.createElement("a");
                var span = document.createElement("span");
                span.innerHTML = " (" + obj.location + ")";
                var ul = document.getElementById(element3);
                var li = document.createElement("li");
                a.textContent = obj.hostname;
                a.setAttribute('href', obj.url);
                li.appendChild(a);
                li.appendChild(span);
                ul.appendChild(li);
                mirrors_rest.push({
                    url:obj.url,
                    hostname:obj.hostname,
                    country:obj.location,
                    lat:obj.lat,
                    lng:obj.lng,
                });
                document.getElementById("h53").innerText = mirrors_rest.length;
            }
            ulh = document.getElementById(element3.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }
        },
        error: function(xhr, ajaxOptions, thrownError, controlToShow) {
            var ulh = document.getElementById(element1.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }
            ulh = document.getElementById(element2.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }
            ulh = document.getElementById(element3.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }

            handleMirrorlistAjaxError(xhr, ajaxOptions, thrownError, element);
        },
    });
}

function toggleMap(lat, lng, idx) {
    var x = document.getElementById(mapAlias[idx]);
    if (x.style.display === "none") {
        initMap(lat, lng, idx);
        x.style.display = "block";
    } else {
        x.style.display = "none";
        mapObject[idx].off();
        mapObject[idx].remove();
        mapObject[idx] = {};
    }
}

function initMap(lat, lng, idx) {
    var center = [0, 0];
    if (mapCenter[idx]) {
        center = [lat, lng];
    }
    mapObject[idx] = L.map(mapAlias[idx]).setView(center, mapScale[idx]);
    var map = mapObject[idx];

    const tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(map);

    var arr;
    switch (idx) {
        case 0:
            arr = mirrors_country;
            break;
        case 1:
            arr = mirrors_region;
            break;
        case 2:
            arr = mirrors_rest;
            break;
        default:
            arr = [].concat(mirrors_country, mirrors_region, mirrors_rest);
    }
    for (const m of arr) {
        var mirrormarker = L.marker([m.lat,m.lng]).addTo(map)
	    .bindPopup('<a href=' + m.url + '>' + (new URL(m.url)).hostname + '</a>');
        if (preferred_url && m.url == preferred_url) {
            mirrormarker._icon.classList.add("huechange1");
        }
    }

    const marker = L.marker([lat, lng]).addTo(map)
        .bindPopup('<i>You</i>');
    marker._icon.classList.add("huechange");

    setTimeout(function(){ map.invalidateSize(); }, 100);
    // setTimeout(function(){ marker.showPopup(); }, 500);
}

