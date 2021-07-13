// jshint multistr: true
// jshint esversion: 6

function handleMirrorlistAjaxError(request, code, error, element) {
    if (request.responseJSON != undefined && request.responseJSON.error) {
        error += ': ' + request.responseJSON.error;
    } else if (request.responseText != undefined && request.responseText) {
        error += ': ' + request.responseText.error;
    }

    element.innerText = 'Error: ' + error;
}

function loadMirrorlist(url, element1, element2, element3) {
    $.ajax({
        url: url,
        method: 'GET',
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
                a.textContent = obj.url;
                a.setAttribute('href', obj.url);
                li.appendChild(a);
                li.appendChild(span);
                ul.appendChild(li);
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
                a.textContent = obj.url;
                a.setAttribute('href', obj.url);
                li.appendChild(a);
                li.appendChild(span);
                ul.appendChild(li);
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
                a.textContent = obj.url;
                a.setAttribute('href', obj.url);
                li.appendChild(a);
                li.appendChild(span);
                ul.appendChild(li);
            }
            ulh = document.getElementById(element2.concat('tohide'));
            if (ulh) {
                ulh.style.display = "none";
            }
        },
        error: function(xhr, ajaxOptions, thrownError, controlToShow) {
            handleMirrorlistAjaxError(xhr, ajaxOptions, thrownError, element);
        },
    });
}
