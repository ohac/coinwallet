$(function(){
  var coinid = $('#coinid').val();
  $.ajax({
    url: '/api/v1/' + coinid + '/balance',
    cache: false,
    dataType: 'json',
    success: function(json){
      var balance = json['balance'];
      $('#balance').text((balance - 0.00005).toFixed(4));
    }
  });
});
