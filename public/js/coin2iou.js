$(function(){
  var coinid = $('#coinid').val();
  $.ajax({
    url: '/api/v1/' + coinid + '/balance',
    cache: false,
    dataType: 'json',
    success: function(json){
      var balance = json['balance'];
      var str = balance > 0.00005 ? (balance - 0.00005).toFixed(4) : '0.0000';
      $('#balance').text(str);
    }
  });
});
