# patch faye's ssl verification so that it works with newer
# Let's Encrypt certs, adapted from:
#   https://github.com/igrigorik/em-http-request/pull/352
# More info from original author:
#   Every LetsEncrypt issued signature chain now starts with an expired certificate,
#   but the second item in the chain is a trusted root. So instead of failing the
#   whole validation for any link in the chain failing, just don't add failed links
#   to the store, then make sure the final certificate is valid given whatever was
#   added to the store.

module Faye
  class WebSocket
    class SslVerifier
      def ssl_verify_peer(cert_text)
        return true unless should_verify?

        certificate = parse_cert(cert_text)
        return false unless certificate

        store_cert(certificate) if @cert_store.verify(certificate)
        @last_cert = certificate

        true
      end

      def identity_verified?
        @last_cert && @cert_store.verify(@last_cert) && OpenSSL::SSL.verify_certificate_identity(@last_cert, @hostname)
      end
    end
  end
end
