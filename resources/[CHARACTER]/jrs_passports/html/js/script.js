

document.addEventListener('DOMContentLoaded', function() {  $("#jrs_passports").fadeOut(); }, false);
function CloseNUI() { $("#jrs_passports").fadeOut(1000); $.post('http://jrs_passports/close', JSON.stringify({})); }

$(function() {

	window.addEventListener('message', function(event) {
		
    var item = event.data;

		if (item.type == "enable") {
			document.body.style.display = item.enable ? "block" : "none";

    } else if (item.action == 'updateInformation'){

      let prod_user = item.info;
      let prod_locale = item.locales;

      $("#main-full-name-title").text(prod_locale.fullname);
      $("#main-full-name-text").text(prod_user.firstname + ' ' + prod_user.lastname);

      $("#main-dob-title").text(prod_locale.dob);
      $("#main-dob-text").text(prod_user.dob);

      $("#main-sex-title").text(prod_locale.sex);
      $("#main-sex-text").text(prod_user.sex);

      $("#main-id-text").text(prod_user.identity_id);
      
      $("#main-signature-title").text(prod_locale.signature);
      $("#main-signature-text").text(prod_user.firstname + ' ' + prod_user.lastname);

      $("#main-expiration-title").text(prod_user.expiration);

      // load avatar image
      $("#main-avatar-image-display").css('background-image', 'url("' + prod_user.avatar_url + '")');

      $("#center-side").show();
      $("#jrs_passports").fadeIn(1000);

    } else if (item.action == "close") {
      CloseNUI();
    }

  });


});