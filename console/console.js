var es;

$(function() {
  var iframe = $('#contentFrame').get(0);
  var sel = $('#samples');
  var tests = $('#tests');
  var nav = $('#nav');
  es = new EventSource('/$console')

  // If a new url is entered, go there
  nav.keyup(function (e) {
    if (e.keyCode == 13) {
      iframe.contentWindow.location = nav.val();
    }
  });

  // If the iframe's url changes, update it
  // There is no event if the frame doesn't actually reload (e.g. fragment changes)
  window.setInterval(function() {
    if($('#nav:focus').length == 0 && nav.val() != iframe.contentWindow.location)
      nav.val(iframe.contentWindow.location);
  }, 100);

  $('#newtab').click(function() {
    var win = window.open(iframe.contentWindow.location, '_blank');
      win.focus();
  });

  es.onmessage = function(event) {
    e = JSON.parse(event.data);
    console.log("Got event " + e.event);
    if(e.event === 'reload') {
      // Reload happens when this script is update
      // Try to remember where we where by storing info in the new querystring
      uri = URI(window.location).removeSearch('__url')
        .addSearch('__url', iframe.contentWindow.location);
      window.location = uri.toString();
    } else if(e.event === 'navigate') {
      iframe.src = e.data.path;
    } else if(e.event === 'refresh') {

      // Repopulate the select dropdown
      sel.empty();
      $.each(e.data, function(key, value){
        sel.append($('<option>').attr('value', key).text(key));
      });
      setSelectedSample();

      // When the sample selection changes, update the querystring
      sel.change(function() {
        var uri = URI(iframe.contentWindow.location).removeSearch('__sample')
          .addSearch('__sample', sel.val());
        iframe.contentWindow.location = uri.toString();
      });

      setTestSelection();
      tests.change(function() {
        var uri = URI(iframe.contentWindow.location).removeSearch('__notests');
        if(tests.prop('checked'))
          uri.addSearch('__notests');
        iframe.contentWindow.location = uri.toString();
      });

      var frameUrl = iframe.contentWindow.location;
      // Set the initial path if it isn't already set
      if(frameUrl == 'about:blank' || frameUrl == '') {
        var search = URI(window.location).search(true);
        var newLocation = search['__url'] ? search['__url'] : '/';
        iframe.contentWindow.location = newLocation;
        nav.val(newLocation);
      } else {
        // Reload the iframe
        iframe.contentWindow.location.reload();
      }
    }
  }

  // When the iframe navigates, refresh the UI
  $('#contentFrame').load(function() {
    setSelectedNav();
    setSelectedSample();
    setTestSelection();
  });

  // Repopulate the nav bar based on the iframe's location
  function setSelectedNav() {
    nav.val(iframe.contentWindow.location);
  }

  // Repopulate the selected sample based on the iframe's querystring
  function setSelectedSample() {
    var search = URI(iframe.contentWindow.location).search(true);
    sel.val(search['__sample'] ? search['__sample'] : 'default');
  }

  // Repopulate the selected sample based on the iframe's querystring
  function setTestSelection() {
    var search = URI(iframe.contentWindow.location).search(true);
    var noTests = search.hasOwnProperty('__notests');
    tests.prop('checked', noTests);
    if(noTests)
      $('#testCell').hide();
    else
      $('#testCell').show();
  }

  // Close the event source before unloading
  function cleanUp() {
    if(es !== null) {
      es.close();
      es = null;
    }
  }
  $(window).on('beforeunload', cleanUp);
  $(window).unload(cleanUp);
});

var qunit = null;
var qunitIsOpen = false;

function showTests() {
  qunitIsOpen = true;
  $(qunit).dialog('open');
}

// Called be the iframe when tests are done
function testsDone(details) {
  // Update the tab title with a check on success or x on fail
  document.title = [
      (details.failed ? "\u2716" : "\u2714" ),
       document.title.replace( /^[\u2714\u2716] /i, "" )
    ].join( " " );

  // Set up the mini-test result display
  var html = '<span class="passed">' + details.passed + '/' + details.total + '</span>';
  if(details.failed > 0)
    html += '<span class="failed">FAILED ' + details.failed + '</span>';
  $('#testResults').html(html);

  // Set up the modal dialog test results display
  qunit = details.qunit;
  $(qunit).dialog({
    autoOpen: false,
    resizable: false,
    modal: true,
    resiable: false,
    width: 800,
    height: 550,
    position: {my: 'center top', at: 'center top+100'},
    dialogClass: 'qunit-dialog',
    close: function () { qunitIsOpen = false; }
  });

  if(qunitIsOpen)
    showTests();
}
